<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Toolchain wrapper for the uv binary.

`UvToolchainInfo.uv` is a `File` for the uv executable. Consumers
resolve it via `ctx.toolchains["@rules_uv//uv:toolchain_type"]`.

The attr uses `allow_single_file = True` rather than
`executable = True` because the bootstrapped binary at `@uv//:binary`
is an alias to a source `File` (cargo_bootstrap_repository's output)
— Bazel rejects source files as executable attr inputs, so we
accept the file and let the consuming rule mark it executable
itself.

<a id="uv_toolchain"></a>

## uv_toolchain

<pre>
load("@rules_uv//uv:toolchains.bzl", "uv_toolchain")

uv_toolchain(<a href="#uv_toolchain-name">name</a>, <a href="#uv_toolchain-uv">uv</a>)
</pre>

Declares a uv toolchain.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="uv_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="uv_toolchain-uv"></a>uv |  Label of the uv binary (either built via cargo_bootstrap_repository or fetched as a prebuilt release asset).   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="UvToolchainInfo"></a>

## UvToolchainInfo

<pre>
load("@rules_uv//uv:toolchains.bzl", "UvToolchainInfo")

UvToolchainInfo(<a href="#UvToolchainInfo-uv">uv</a>)
</pre>

Information about a uv toolchain.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvToolchainInfo-uv"></a>uv |  File pointing at the `uv` executable.    |


