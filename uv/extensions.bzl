"""Module extension that fetches uv's source and bootstraps the binary.

Produces two repos:

  @uv_source   astral-sh/uv source tarball at the pinned version,
               overlaid with a BUILD file that exposes Cargo.toml /
               Cargo.lock / a `:srcs` filegroup.
  @uv          built `uv` binary, via rules_rust's
               `cargo_bootstrap_repository` (which shells out to a
               real `cargo build --release -p uv`).

Building uv from source is genuinely heavy — it pulls hundreds of
crates from crates.io and compiles them in release mode. Rust 1.95
satisfies uv's MSRV and edition-2024 requirement. Expect a long
first build; subsequent ones are cached by Bazel as a repository
rule output.

Pin a different uv version by registering the `toolchain` tag:

    uv = use_extension("@rules_uv//uv:extensions.bzl", "uv")
    uv.toolchain(version = "0.11.16")
    use_repo(uv, "uv", "uv_source")
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@rules_rust//cargo:defs.bzl", "cargo_bootstrap_repository")
load("//uv/private:known_versions.bzl", "DEFAULT_VERSION", "KNOWN_VERSIONS", "URL_TEMPLATE")

def _uv_extension_impl(mctx):
    version = DEFAULT_VERSION
    for mod in mctx.modules:
        for tag in mod.tags.toolchain:
            if tag.version:
                version = tag.version

    sha256 = KNOWN_VERSIONS.get(version, "")
    if not sha256:
        # Unpinned versions emit a warning rather than failing — keeps
        # `uv.toolchain(version = "<new>")` ergonomic for bumps.
        # http_archive will recompute and embed the hash on first
        # fetch.
        print("rules_uv: uv version {} is not in known_versions.bzl; fetching unpinned".format(version))  # buildifier: disable=print

    http_archive(
        name = "uv_source",
        url = URL_TEMPLATE.format(version = version),
        sha256 = sha256,
        # GitHub source tarballs wrap everything in a `<repo>-<version>` dir.
        strip_prefix = "uv-{}".format(version),
        build_file = "@rules_uv//uv/private:uv_source.BUILD.bazel",
    )

    # rules_rust under bzlmod canonicalizes the toolchain tools repos
    # as `@@rules_rust++rust+rust_<system>_<arch>__<triple>__<channel>_tools`,
    # so the default templates (`@rust_..._tools//...`) don't resolve.
    # Inline the canonical prefix so cargo_bootstrap_repository finds
    # `cargo` / `rustc` regardless of the consumer's repo namespace.
    _CARGO_TEMPLATE = "@@rules_rust++rust+rust_{system}_{arch}__{triple}__{channel}_tools//:bin/{tool}"

    cargo_bootstrap_repository(
        name = "uv",
        cargo_lockfile = "@uv_source//:Cargo.lock",
        cargo_toml = "@uv_source//:Cargo.toml",
        srcs = ["@uv_source//:srcs"],
        binary = "uv",
        version = "1.95.0",
        build_mode = "release",
        rust_toolchain_cargo_template = _CARGO_TEMPLATE,
        rust_toolchain_rustc_template = _CARGO_TEMPLATE,
        # uv's build occasionally takes longer than the default 600s
        # ceiling on cold builds (clean crates.io cache, no sccache).
        timeout = 1800,
    )

_toolchain_tag = tag_class(attrs = {
    "version": attr.string(
        default = "",
        doc = "Override uv version. Defaults to known_versions.DEFAULT_VERSION.",
    ),
})

uv = module_extension(
    implementation = _uv_extension_impl,
    tag_classes = {"toolchain": _toolchain_tag},
    doc = "Fetches uv source and bootstraps the uv binary via cargo.",
)
