"""Toolchain wrapper for the uv binary.

`UvToolchainInfo.uv` is a `File` for the uv executable. Consumers
resolve it via `ctx.toolchains["@rules_uv//uv:toolchain_type"]`.
"""

UvToolchainInfo = provider(
    doc = "Information about a uv toolchain.",
    fields = {
        "uv": "File pointing at the `uv` executable.",
    },
)

def _uv_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            uv_info = UvToolchainInfo(uv = ctx.executable.uv),
            # Make the binary directly available too for callers
            # that prefer DefaultInfo over the provider above.
            default = DefaultInfo(
                files = depset([ctx.executable.uv]),
                executable = ctx.executable.uv,
            ),
        ),
    ]

uv_toolchain = rule(
    implementation = _uv_toolchain_impl,
    attrs = {
        "uv": attr.label(
            executable = True,
            cfg = "exec",
            mandatory = True,
            doc = "Label of the uv binary produced by cargo_bootstrap_repository.",
        ),
    },
    doc = "Declares a uv toolchain.",
)
