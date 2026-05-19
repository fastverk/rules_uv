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

## v0.3 (next)

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
  editable is a v0.4 conversation.

## Beyond v0.3

- `uv_pip_compile`: `bazel run`-able workflow to regenerate
  `requirements.txt` from a `pyproject.toml` (analogous to rules_uv
  upstream's compile workflow).
- Cross-platform wheels: support emitting `select()` deps when a
  package has multiple platform wheels but the consumer wants to
  target several configurations from one tree.
- Stardoc-generated reference in `/docs`.
