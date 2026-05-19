<!-- Generated with Stardoc: http://skydoc.bazel.build -->

`pip_parse` module extension — uv.lock → @<hub> + per-pkg repos.

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

<a id="pip"></a>

## pip

<pre>
pip = use_extension("@rules_uv//pip:extensions.bzl", "pip")
pip.parse(<a href="#pip.parse-hub_name">hub_name</a>, <a href="#pip.parse-lock">lock</a>, <a href="#pip.parse-platforms">platforms</a>, <a href="#pip.parse-python">python</a>, <a href="#pip.parse-python_version">python_version</a>, <a href="#pip.parse-uv">uv</a>)
</pre>

Materialize @<hub> + per-pkg repos from a uv.lock.


**TAG CLASSES**

<a id="pip.parse"></a>

### parse

**Attributes**

| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="pip.parse-hub_name"></a>hub_name |  Name of the hub repo (the @<hub_name>//... namespace).   | String | optional |  `"pip"`  |
| <a id="pip.parse-lock"></a>lock |  Label pointing at a uv.lock file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="pip.parse-platforms"></a>platforms |  Optional list of `<os>_<arch>` platforms this lockfile should support. Default is host-only (the v0.4 behavior — `select()` is not introduced). Supported entries: darwin_aarch64, darwin_x86_64, linux_aarch64, linux_x86_64. Packages with platform-divergent native wheels fan out into per-platform repos behind a select() alias; sdist/git/path packages remain host-only and the build will fail loudly if a non-host platform tries to resolve them.   | List of strings | optional |  `[]`  |
| <a id="pip.parse-python"></a>python |  How to find a Python interpreter for sdist install. `host` uses `python3` on PATH; `uv` runs `uv python install <python_version>` per package.   | String | optional |  `"host"`  |
| <a id="pip.parse-python_version"></a>python_version |  Python `major.minor` used for wheel-tag matching and (when python = "uv") the uv-managed interpreter.   | String | optional |  `"3.12"`  |
| <a id="pip.parse-uv"></a>uv |  Label of the uv binary used to install sdists.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@uv"`  |


