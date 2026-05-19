"""`pip_parse` module extension — uv.lock → @<hub> + per-pkg repos.

Counterpart to rules_python's `pip_parse`, but driven by uv.lock
instead of requirements.txt. For each package the lockfile resolves
to, we create a Bazel-fetched repo containing the unpacked wheel
(or installed sdist, or fetched git/path source). A hub repo
aggregates these and exposes a `requirement("<name>")` macro plus
pre-aliased `@<hub>//<name>:pkg` labels.

Consumer:

    pip = use_extension("@rules_uv//pip:extensions.bzl", "pip")
    pip.parse(
        hub_name = "pip",
        lock = "//:uv.lock",
        python_version = "3.12",
    )
    use_repo(pip, "pip")

Extras are exposed as additional sub-targets on the package repo:

    load("@pip//:requirements.bzl", "requirement")
    py_library(
        name = "app",
        deps = [
            requirement("requests"),              # base package
            requirement("requests[security]"),    # base + extra deps
        ],
    )

Markers (e.g. `marker = "python_version < '3.11'"`) are evaluated
at extension time against the configured `python_version` + host
platform. Edges whose markers fail are silently dropped from the
generated BUILD — keeping the host-only view simple. Cross-platform
`select()` is v0.5.
"""

load(
    "@bazel_tools//tools/build_defs/repo:git.bzl",
    "new_git_repository",
)
load(
    "@bazel_tools//tools/build_defs/repo:http.bzl",
    "http_archive",
)
load("//pip/private:markers.bzl", "eval_marker", "host_env")
load("//pip/private:platform.bzl", "host_platform")
load("//pip/private:sdist_install.bzl", "sdist_install_repo")
load("//pip/private:wheel_selection.bzl", "select_artifact")

# -----------------------------------------------------------------------------
# Per-package repo creation. Dispatches on source kind first
# (registry/url -> wheel/sdist; git -> new_git_repository; path ->
# pip_path_repo), then within the wheel/sdist case dispatches on
# artifact kind.
# -----------------------------------------------------------------------------

def _filter_deps(deps, env, name):
    """Return the list of dep names whose markers pass against `env`.

    Multi-extra and extra-gated deps are filtered out here too —
    they live in the per-extra dep set, not the unconditional one.
    """
    out = []
    seen = {}
    for d in deps:
        if d.get("extra"):
            continue
        if not eval_marker(d.get("marker", ""), env):
            continue
        n = d.get("name")
        if not n or n == name:
            continue
        if n in seen:
            continue
        seen[n] = True
        out.append(n)
    return out

def _extras_dep_sets(pkg, env):
    """For each extra defined on `pkg`, build the filtered dep list.

    Each entry: `(extra_name, [base_dep_pkg_name, ...])`.

    Pulls from:
      * `pkg.optional_dependencies` (the package's own extras
        table, lifted from `[package.metadata]`).
      * `pkg.dependencies` entries that carry `extra = "..."`
        (gated edges).
    """
    out = {}

    # 1. Edges with explicit `extra = "..."` on the dependency
    # itself (uv records these on the dependent package's side).
    for d in pkg.get("dependencies", []):
        extra = d.get("extra") or ""
        if not extra:
            continue
        if not eval_marker(d.get("marker", ""), env):
            continue
        out.setdefault(extra, [])
        out[extra].append(d.get("name", ""))

    # 2. `optional-dependencies` table — the dependent package's
    # canonical extras → dep-name list.
    for extra, names in pkg.get("optional_dependencies", {}).items():
        out.setdefault(extra, [])
        for n in names:
            if n not in out[extra] and n != pkg.get("name"):
                out[extra].append(n)

    # Normalize: stable ordering, deduplicate.
    sorted_out = {}
    for extra in sorted(out.keys()):
        sorted_out[extra] = sorted({n: True for n in out[extra]}.keys())
    return sorted_out

def _make_pkg_repo(hub_name, pkg, build_tpl, host, python_version,
                   python_strategy, uv_label):
    source = pkg.get("source", {})
    kind = source.get("kind", "unknown")
    repo_name = _pkg_repo_name(hub_name, pkg["name"])

    env = host_env(host, python_version)
    unconditional_deps = _filter_deps(pkg.get("dependencies", []), env, pkg["name"])
    dep_labels = [_dep_label(hub_name, d) for d in unconditional_deps]

    extras = _extras_dep_sets(pkg, env)
    extra_target_blocks = []
    for extra, dep_names in extras.items():
        labels = [_dep_label(hub_name, d) for d in dep_names]
        extra_target_blocks.append(_render_extra_target(extra, labels))
    extra_targets_str = "\n".join(extra_target_blocks)

    build_file_content = build_tpl \
        .replace("{NAME}", pkg["name"]) \
        .replace("{VERSION}", pkg.get("version", "")) \
        .replace("{DEPS}", _labels_str(dep_labels)) \
        .replace("{EXTRA_TARGETS}", extra_targets_str)

    if kind == "git":
        # uv normalizes the rev in `source.rev`. Git sources have no
        # wheel — Bazel fetches the repo and we trust the project's
        # own setup.py / pyproject.toml to be importable as a tree.
        # Consumers that need a build step can layer `genrule` or
        # `py_wheel` on top via a patch.
        new_git_repository(
            name = repo_name,
            remote = source.get("git", ""),
            commit = source.get("rev", ""),
            build_file_content = build_file_content,
        )
        return

    if kind == "path":
        # Path sources point at a sibling directory inside the
        # consumer's workspace. We use `new_local_repository` so
        # Bazel sees it as a real repo (and re-fetches on changes).
        # The relative path is resolved against the workspace
        # root, not the lockfile's directory — same semantics as
        # uv itself.
        _path_repo(
            name = repo_name,
            path = source.get("path", ""),
            build_file_content = build_file_content,
        )
        return

    if kind == "editable":
        # Editable sources only make sense inside `uv run`. For
        # Bazel they're effectively path sources with a develop-
        # install gloss. Emit a clear error rather than silently
        # producing a broken target.
        fail(
            "rules_uv/pip: package {} uses an editable source. " +
            "Editable installs are not supported in Bazel — convert " +
            "to a path source or to a normal sdist/wheel entry.".format(
                pkg["name"],
            ),
        )

    # Default = registry/url. Select wheel vs sdist via
    # wheel_selection, then fan out.
    artifact = select_artifact(pkg, host, python_version)
    if artifact.kind == "wheel":
        http_archive(
            name = repo_name,
            url = artifact.url,
            sha256 = artifact.sha256,
            type = "zip",
            build_file_content = build_file_content,
        )
    else:
        sdist_install_repo(
            name = repo_name,
            url = artifact.url,
            sha256 = artifact.sha256,
            pkg_name = pkg["name"],
            pkg_version = pkg.get("version", ""),
            deps = dep_labels,
            uv = uv_label,
            python_strategy = python_strategy,
            python_version = python_version,
        )

# -----------------------------------------------------------------------------
# Hub repo — emits `requirements.bzl` with the `requirement()` macro.
# -----------------------------------------------------------------------------

def _hub_repo_impl(repository_ctx):
    package_names = repository_ctx.attr.package_names
    hub_name = repository_ctx.attr.hub_name

    alias_entries = []
    requirement_entries = []
    for name in package_names:
        norm = _normalize(name)
        alias_entries.append(
            'alias(name = "{n}", actual = "@{hub}__{n}//:pkg")'.format(
                n = norm,
                hub = hub_name,
            ),
        )
        requirement_entries.append(
            '    "{}": Label("@{}//:{}"),'.format(norm, hub_name, norm),
        )

    # Extras live in the per-package repos; the hub just needs to
    # know which base packages exist so `requirement("foo[bar]")`
    # can rewrite to `@<hub>__foo//:bar`. The macro below does that.
    repository_ctx.file("BUILD.bazel", """\
package(default_visibility = ["//visibility:public"])
exports_files(["requirements.bzl"])

{aliases}
""".format(aliases = "\n".join(alias_entries)))

    repository_ctx.file("requirements.bzl", """\
\"\"\"Generated by rules_uv//pip:extensions.bzl. Do not edit.\"\"\"

_REQUIREMENTS = {{
{entries}
}}

_HUB = "{hub}"

def requirement(name):
    \"\"\"Resolve a package name (with optional extra) to its Bazel label.

    Forms:
      requirement("requests")            → @<hub>//:requests
      requirement("requests[security]")  → @<hub>__requests//:security
    \"\"\"
    norm, extra = _split_extra(name)
    if norm not in _REQUIREMENTS:
        fail("rules_uv/pip: unknown package '{{}}' (known: {{}})".format(
            name, sorted(_REQUIREMENTS.keys()),
        ))
    if extra:
        return Label("@{{}}__{{}}//:{{}}".format(_HUB, norm, extra))
    return _REQUIREMENTS[norm]

def _split_extra(name):
    \"\"\"Parse 'pkg[extra]' → (pkg, extra). Returns (pkg, '') if no extra.\"\"\"
    lbracket = name.find("[")
    if lbracket < 0:
        return _norm(name), ""
    rbracket = name.find("]", lbracket)
    if rbracket < 0:
        fail("rules_uv/pip: malformed requirement {{!r}} (missing ])".format(name))
    return _norm(name[:lbracket]), name[lbracket + 1:rbracket]

def _norm(name):
    return name.lower().replace("_", "-").replace(".", "-")

ALL_REQUIREMENTS = [v for _, v in sorted(_REQUIREMENTS.items())]
""".format(
        entries = "\n".join(requirement_entries),
        hub = hub_name,
    ))

_hub_repo = repository_rule(
    implementation = _hub_repo_impl,
    attrs = {
        "hub_name": attr.string(mandatory = True),
        "package_names": attr.string_list(mandatory = True),
    },
)

# -----------------------------------------------------------------------------
# Path-source repo — thin wrapper around new_local_repository that
# accepts the same build_file_content we generate for everything else.
# -----------------------------------------------------------------------------

def _path_repo_impl(rctx):
    src = rctx.workspace_root.get_child(rctx.attr.path)
    if not src.exists:
        fail(
            "rules_uv/pip: path source {!r} does not exist " +
            "(resolved from workspace root: {})".format(
                rctx.attr.path,
                src,
            ),
        )
    rctx.symlink(src, ".")
    rctx.file("BUILD.bazel", rctx.attr.build_file_content)

_path_repo = repository_rule(
    implementation = _path_repo_impl,
    attrs = {
        "path": attr.string(mandatory = True),
        "build_file_content": attr.string(mandatory = True),
    },
    doc = "Symlink a workspace-relative path source into a Bazel repo.",
)

# -----------------------------------------------------------------------------
# Top-level: read uv.lock via tomllib (python3.11 helper) and fan out.
# -----------------------------------------------------------------------------

def _read_lock(mctx, lock_label):
    lock_path = mctx.path(lock_label)
    script = mctx.path(Label("//pip/private:uvlock_to_json.py"))
    python = mctx.which("python3") or mctx.which("python")
    if not python:
        fail("rules_uv/pip: no python3 on PATH — needed to parse uv.lock " +
             "(uses Python's stdlib tomllib).")
    result = mctx.execute([python, script, lock_path], quiet = True)
    if result.return_code != 0:
        fail("rules_uv/pip: uvlock_to_json failed: " + result.stderr)
    return json.decode(result.stdout)

def _pip_extension_impl(mctx):
    build_tpl_path = mctx.path(
        Label("//pip/private:pip_package.BUILD.tpl"),
    )
    build_tpl = mctx.read(build_tpl_path)
    host = host_platform(mctx)

    for mod in mctx.modules:
        for tag in mod.tags.parse:
            lock = _read_lock(mctx, tag.lock)
            pkg_names = []
            for pkg in lock["packages"]:
                kind = pkg.get("source", {}).get("kind", "unknown")
                if kind == "virtual":
                    # The project itself; never materialized.
                    continue
                if kind == "unknown":
                    fail(
                        "rules_uv/pip: package {} has an unrecognized " +
                        "source. Lockfile must use one of: registry, " +
                        "url, git, path, editable, virtual.".format(
                            pkg.get("name", "<unnamed>"),
                        ),
                    )
                _make_pkg_repo(
                    hub_name = tag.hub_name,
                    pkg = pkg,
                    build_tpl = build_tpl,
                    host = host,
                    python_version = tag.python_version,
                    python_strategy = tag.python,
                    uv_label = tag.uv,
                )
                pkg_names.append(pkg["name"])
            _hub_repo(
                name = tag.hub_name,
                hub_name = tag.hub_name,
                package_names = pkg_names,
            )

_parse_tag = tag_class(attrs = {
    "hub_name": attr.string(
        default = "pip",
        doc = "Name of the hub repo (the @<hub_name>//... namespace).",
    ),
    "lock": attr.label(
        mandatory = True,
        allow_single_file = True,
        doc = "Label pointing at a uv.lock file.",
    ),
    "python_version": attr.string(
        default = "3.12",
        doc = "Python `major.minor` used for wheel-tag matching " +
              "and (when python = \"uv\") the uv-managed interpreter.",
    ),
    "python": attr.string(
        default = "host",
        values = ["host", "uv"],
        doc = "How to find a Python interpreter for sdist install. " +
              "`host` uses `python3` on PATH; `uv` runs " +
              "`uv python install <python_version>` per package.",
    ),
    "uv": attr.label(
        # Both extension modes expose `@uv//:uv` as the canonical
        # uv-binary File label.
        default = "@uv//:uv",
        doc = "Label of the uv binary used to install sdists.",
    ),
})

pip = module_extension(
    implementation = _pip_extension_impl,
    tag_classes = {"parse": _parse_tag},
    doc = "Materialize @<hub> + per-pkg repos from a uv.lock.",
)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

def _normalize(name):
    # PEP 503 canonical name: lowercase, _/. → -.
    return name.lower().replace("_", "-").replace(".", "-")

def _pkg_repo_name(hub_name, pkg_name):
    return "{}__{}".format(hub_name, _normalize(pkg_name))

def _dep_label(hub_name, pkg_name):
    return "@{}__{}//:pkg".format(hub_name, _normalize(pkg_name))

def _labels_str(labels):
    return ", ".join(['"{}"'.format(l) for l in labels])

def _render_extra_target(extra, dep_labels):
    """Emit a `py_library` for one extra. Re-exports `:pkg` plus extra deps."""
    base = "\":pkg\""
    deps = [base] + ['"{}"'.format(l) for l in dep_labels]
    return """\

py_library(
    name = "{extra}",
    deps = [{deps}],
)
""".format(extra = extra, deps = ", ".join(deps))
