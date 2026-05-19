#!/usr/bin/env bash
# Escape the Bazel sandbox so uv operates on the live workspace
# (uv pip sync / uv lock / uv run all need to write into the user's
# source tree).
#
# Inputs (set by the uv_run macro via sh_binary env):
#   UV_RUN_SUBCOMMAND   — first uv arg (e.g. "pip", "lock", "run", …)
#   UV_RUN_EXTRA_ARGS   — extra args appended after the subcommand
set -euo pipefail

if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  echo "error: must be invoked via 'bazel run'" >&2
  exit 1
fi

RUNFILES_DIR="${RUNFILES_DIR:-$0.runfiles}"
# Walk symlinks (Bazel materializes runfiles as symlinks pointing
# into the output base) and accept any path basename'd `uv`.
UV_BIN="$(find -L "$RUNFILES_DIR" -name uv -type f -perm -u+x 2>/dev/null | head -1)"
if [[ -z "$UV_BIN" ]]; then
  echo "error: cannot locate uv binary in runfiles ($RUNFILES_DIR)" >&2
  exit 2
fi

# Telemetry / determinism pins. NO_COLOR matches what we do in
# rules_bun; uv honors it.
export NO_COLOR="${NO_COLOR:-1}"

cd "${BUILD_WORKSPACE_DIRECTORY}"
# shellcheck disable=SC2086
exec "$UV_BIN" "${UV_RUN_SUBCOMMAND:?UV_RUN_SUBCOMMAND env must be set by uv_run macro}" \
  ${UV_RUN_EXTRA_ARGS} "$@"
