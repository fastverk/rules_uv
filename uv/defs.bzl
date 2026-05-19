"""User-facing rules for rules_uv.

  * `uv_run` — sh_binary macro: `bazel run //path:NAME` invokes
    `uv <subcommand>` against the live workspace source. Intentionally
    non-hermetic (escapes the runfiles sandbox) for the dev loop
    (`uv pip sync`, `uv lock`, `uv run …`).

Lockfile-driven Python repo materialization lives in
`@rules_uv//pip:extensions.bzl` (`pip_parse`), which is the rules_uv
analogue of rules_python's `pip_parse` but reads `uv.lock` rather
than `requirements.txt`.
"""

load("@rules_shell//shell:sh_binary.bzl", _sh_binary = "sh_binary")

def uv_run(name, subcommand, args = None, **kwargs):
    """`bazel run`-able wrapper around `uv <subcommand>`.

    Escapes the runfiles sandbox via BUILD_WORKSPACE_DIRECTORY so uv
    operates on the user's source tree (`uv lock`, `uv pip sync …`
    both need to write into the workspace).

    Args:
      name: target name.
      subcommand: first arg passed to uv (e.g. `pip`, `lock`, `run`).
      args: extra args appended after the subcommand.
      **kwargs: forwarded to the underlying `sh_binary`.
    """
    extra = " ".join(args) if args else ""
    _sh_binary(
        name = name,
        srcs = ["@rules_uv//uv/private:uv_run.sh"],
        data = ["@uv//:binary"],
        env = {
            "UV_RUN_SUBCOMMAND": subcommand,
            "UV_RUN_EXTRA_ARGS": extra,
        },
        **kwargs
    )
