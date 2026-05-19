"""Toolchain wrapper for the uv binary.

`UvToolchainInfo.uv` is a `File` for the uv executable. Consumers
resolve it via `ctx.toolchains["@rules_uv//uv:toolchain_type"]`.

The attr uses `allow_single_file = True` rather than
`executable = True` because the bootstrapped binary at `@uv//:binary`
is an alias to a source `File` (cargo_bootstrap_repository's output)
— Bazel rejects source files as executable attr inputs, so we
accept the file and let the consuming rule mark it executable
itself.
"""

UvToolchainInfo = provider(
    doc = "Information about a uv toolchain.",
    fields = {
        "uv": "File pointing at the `uv` executable.",
    },
)

def _uv_toolchain_impl(ctx):
    return [platform_common.ToolchainInfo(
        uv_info = UvToolchainInfo(uv = ctx.file.uv),
    )]

uv_toolchain = rule(
    implementation = _uv_toolchain_impl,
    attrs = {
        "uv": attr.label(
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
            doc = "Label of the uv binary (either built via " +
                  "cargo_bootstrap_repository or fetched as a " +
                  "prebuilt release asset).",
        ),
    },
    doc = "Declares a uv toolchain.",
)
