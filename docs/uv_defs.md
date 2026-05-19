<!-- Generated with Stardoc: http://skydoc.bazel.build -->

User-facing rules for rules_uv.

  * `uv_run` — sh_binary macro: `bazel run //path:NAME` invokes
    `uv <subcommand>` against the live workspace source. Intentionally
    non-hermetic (escapes the runfiles sandbox) for the dev loop
    (`uv pip sync`, `uv lock`, `uv run …`).

Lockfile-driven Python repo materialization lives in
`@rules_uv//pip:extensions.bzl` (`pip_parse`), which is the rules_uv
analogue of rules_python's `pip_parse` but reads `uv.lock` rather
than `requirements.txt`.

<a id="uv_run"></a>

## uv_run

<pre>
load("@rules_uv//uv:defs.bzl", "uv_run")

uv_run(<a href="#uv_run-name">name</a>, <a href="#uv_run-subcommand">subcommand</a>, <a href="#uv_run-args">args</a>, <a href="#uv_run-kwargs">**kwargs</a>)
</pre>

`bazel run`-able wrapper around `uv <subcommand>`.

Escapes the runfiles sandbox via BUILD_WORKSPACE_DIRECTORY so uv
operates on the user's source tree (`uv lock`, `uv pip sync …`
both need to write into the workspace).


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_run-name"></a>name |  target name.   |  none |
| <a id="uv_run-subcommand"></a>subcommand |  first arg passed to uv (e.g. `pip`, `lock`, `run`).   |  none |
| <a id="uv_run-args"></a>args |  extra args appended after the subcommand.   |  `None` |
| <a id="uv_run-kwargs"></a>kwargs |  forwarded to the underlying `sh_binary`.   |  none |


