# rules_uv roadmap

## v0.1

- [x] `@uv//:binary` built from source via `cargo_bootstrap_repository`.
- [x] `uv_run` macro: sandbox-escaping `bazel run` wrapper.
- [x] `pip.parse` module extension: `uv.lock` → `@pip` hub +
      per-package repos.
- [x] Pure-Python wheel materialization (`py3-none-any`).
- [x] Sdist fallback (raw download; no build step yet).
- [x] End-to-end smoke test in `examples/smoke`.

## v0.2 (this release)

- [x] **Prebuilt-uv toolchain alternative.** `uv.toolchain(source =
      "prebuilt")` fetches the official release asset for the host
      platform from `astral-sh/uv` releases. Supported hosts today:
      `darwin_{aarch64,x86_64}` and `linux_{aarch64,x86_64}`.
      musl + 32-bit + Windows triples are intentionally omitted
      until someone needs them — pinning shas we never test is
      security theater.
- [x] **Unified target shape.** Both `build` and `prebuilt` produce
      `@uv//:binary` as a `File`; `uv_toolchain` accepts the file
      directly (no more `:install` rust_binary indirection).

## v0.3 (this release)

- [x] **Native wheel selection.** PEP 425 / PEP 600 tag scoring in
      `pip/private/wheel_selection.bzl`: parse wheel filenames, fan
      out compressed tag fields, score against a host-specific
      ordered tag list (`pip/private/platform.bzl`). MVP covers the
      4 fastverk hosts (`darwin_{aarch64,x86_64}`,
      `linux_{aarch64,x86_64}`); rules_python's
      `whl_target_platforms` is more thorough and will be the
      backing implementation once their internals stabilize.
- [x] **Sdist installation via uv.** `sdist_install_repo`
      (`pip/private/sdist_install.bzl`): downloads the sdist,
      shells to `@uv//:uv` (`uv pip install --target=. --no-deps`)
      at repo-rule time. Python interpreter via `python = "host"`
      (`python3` on PATH) or `python = "uv"` (`uv python install`
      into a per-repo scratch dir).
- [x] **`python_version` + `python` attrs on `pip.parse`.** Wheel
      tag matching consults `python_version`; sdist install
      dispatches on `python`.

## v0.4 (next)

### Lockfile coverage gaps

`uvlock_to_json.py` still drops several lockfile fields:

- `optional-dependencies` (extras): we'd need a story for whether
  extras compile into separate Bazel targets (`@pip//foo:bar[extra]`)
  or into transitive deps gated by a flag.
- `marker` (per-dep environment markers): `os_name == "posix"` etc.
  Should map onto Bazel `select()` — same pattern rules_python uses.
- Git + path + editable sources: skipped entirely. Path is the
  easiest (just a `local_repository`); git is `git_repository`;
  editable is a v0.5 conversation.

### Cross-platform wheels

When a lockfile carries wheels for multiple platforms (and the
consumer wants to target several configurations from one tree),
emit `select()` deps so the right wheel ships per platform. Today
wheel selection happens once at repo-rule time against the host;
this would push selection to analysis time.

## Beyond v0.4

- `uv_pip_compile`: `bazel run`-able workflow to regenerate
  `requirements.txt` from a `pyproject.toml` (analogous to rules_uv
  upstream's compile workflow).
- Cross-platform wheels: support emitting `select()` deps when a
  package has multiple platform wheels but the consumer wants to
  target several configurations from one tree.
- Stardoc-generated reference in `/docs`.

## Delete `uv/` when rules_python's uv is stable

rules_python ships its own experimental uv toolchain primitive at
`@rules_python//python/uv:uv_toolchain.bzl` and a binary-fetching
module extension at `@rules_python//python/uv:uv.bzl`. Both are
marked `EXPERIMENTAL: This is experimental and may be removed
without notice`, so today rules_uv carries its own toolchain +
fetch + build paths.

When rules_python promotes these out of experimental, rules_uv's
`uv/` directory becomes pure duplication and should be removed:

  * Drop `uv/extensions.bzl`, `uv/toolchains.bzl`,
    `uv/private/known_versions.bzl`, `uv/private/uv_source.BUILD.bazel`.
  * Replace our `uv_run` macro with one that resolves through
    rules_python's `uv_toolchain_type`.
  * The pip extension keeps using `@uv//:binary` at repo-rule time
    (just pointing at whichever target rules_python's extension
    materializes by then).

This trims rules_uv down to its actual reason for existing: the
uv.lock TOML → `@pip` materializer. Track upstream status at
`https://github.com/bazelbuild/rules_python/issues/` (search for
"uv toolchain experimental").
