# rules_uv roadmap

## v0.1 (this release)

- [x] `@uv//:binary` built from source via `cargo_bootstrap_repository`.
- [x] `uv_run` macro: sandbox-escaping `bazel run` wrapper.
- [x] `pip.parse` module extension: `uv.lock` → `@pip` hub +
      per-package repos.
- [x] Pure-Python wheel materialization (`py3-none-any`).
- [x] Sdist fallback (raw download; no build step yet).
- [x] End-to-end smoke test in `examples/smoke`.

## v0.2 (next)

Two themes — completeness, and giving consumers a fast path that
skips the 12-minute cold build.

### Native wheel selection

Today the per-package repo rule only picks the pure-Python wheel
(or sdist fallback). Real consumers want platform-specific wheels:
`*-manylinux_2_28_x86_64.whl`, `*-macosx_11_0_arm64.whl`,
`*-win_amd64.whl`. The selection needs:

1. Resolve the host triple at repo-rule time.
2. Compute the PEP 425 / PEP 600 tag set for that triple.
3. Pick the highest-priority wheel whose tags are a subset of the
   host's.

rules_python's `whl_target_platforms.bzl` already does this and is
the reference implementation. The work for rules_uv is to port the
table + scoring logic — no new design needed.

### Prebuilt-uv toolchain alternative

12 minutes for a cold build is the right move when the user wants
hermeticity and reproducibility, but it's overkill for many setups.
Add a second toolchain backed by `rules_github`-fetched releases
from `astral-sh/uv` (the same pattern rules_bun + rules_mdbook use)
so consumers can pick:

- `uv.toolchain(source = "build")` (default) — current behavior.
- `uv.toolchain(source = "prebuilt")` — fetch the official release
  binary for the host triple.

### Sdist installation

Today sdists land on disk as a raw tarball and the `py_library`
globs the layout that happens to result from `http_file`. A real
install step would shell to `uv pip install --target=<dir>` (we
have `@uv//:binary` available!) so consumers get a working
import tree for every package, not just pure-Python ones.

### Lockfile coverage gaps

`uvlock_to_json.py` drops several lockfile fields today:

- `optional-dependencies` (extras): we'd need a story for whether
  extras compile into separate Bazel targets (`@pip//foo:bar[extra]`)
  or into transitive deps gated by a flag.
- `marker` (per-dep environment markers): `os_name == "posix"` etc.
  Should map onto Bazel `select()` — same pattern rules_python uses.
- Git + path + editable sources: skipped entirely. Path is the
  easiest (just a `local_repository`); git is `git_repository`;
  editable is a v0.3 conversation.

## Beyond v0.2

- `uv_pip_compile`: `bazel run`-able workflow to regenerate
  `requirements.txt` from a `pyproject.toml` (analogous to rules_uv
  upstream's compile workflow).
- Cross-platform wheels: support emitting `select()` deps when a
  package has multiple platform wheels but the consumer wants to
  target several configurations from one tree.
- Stardoc-generated reference in `/docs`.
