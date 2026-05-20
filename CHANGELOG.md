# Changelog

All notable changes to rules_uv. The format is loosely
[Keep a Changelog](https://keepachangelog.com/) — version headers
mirror the published bazel-registry entries.

## 0.7.0 — editable workspace roots + PEP 735 dependency groups

- **Editable workspace roots are now skipped, not rejected.** uv
  writes `source = { editable = "." }` on the project's own entry
  in `uv.lock`; v0.5 explicitly failed with "convert to a path
  source". v0.7 skips the entry silently — the consumer's source
  already lives in their own Bazel targets — but still mines the
  attached `dev-dependencies` table for dep-groups (see below).
  Closes the v0.6 compatibility gap that blocked uv workspaces.
- **PEP 735 dependency groups** are now first-class. The lockfile
  parser (`uvlock_to_json.py`) hoists `[package.dev-dependencies]`
  (which despite the name carries every named group — `dev`,
  `test`, `docs`, …) to a top-level map. Per-edge markers and
  extras are honoured. The hub repo emits a new `group(name)`
  macro alongside `requirement()`:

  ```python
  load("@pip//:requirements.bzl", "requirement", "group")
  py_test(
      name = "tests",
      deps = [requirement("my_lib")] + group("dev"),
  )
  ```

  `ALL_GROUPS` constant lists every defined group name for
  introspection. Unknown group name fails the load with the known
  set.
- Smoke fixture now exercises both: lockfile's `smoke` entry is
  `editable = "."` with a `dev = [{name = "iniconfig"}]` group;
  `examples/smoke:smoke_test` pulls iniconfig via `group("dev")`.

## 0.6.0 — pure-Python sdists in multi-platform mode

- Pure-Python sdists are now allowed in `pip.parse(platforms = ...)`
  lockfiles. The extension installs the sdist once on the host
  with `sdist_install_repo(forbid_native_extensions = True)`; the
  result is a single platform-agnostic repo shared by every
  target platform (same shape as a pure-Python wheel — no
  selector needed). v0.5 had this case fail loudly; the v0.6 path
  closes the gap for the common case (one-file utility packages
  that never bothered shipping wheels — `six` 1.4.1 is the smoke-
  test case in `examples/multiplatform/`).
- Sdists that produce native extensions on the host install
  (`.so` / `.pyd` / `.dylib` / `.dll` files in the repo root)
  still fail loudly — cross-arch reuse of a host-built native
  extension would silently link wrong-arch binaries into other
  platforms. The error message points at the alternatives (pin a
  wheel, or drop the unsupported platform from `platforms`).
- New `sdist_install_repo(forbid_native_extensions)` attr;
  default `False` so single-platform host-only installs work
  exactly like before.

## 0.5.1 — docs + CI infrastructure

- Stardoc-generated reference docs in `docs/` for `uv_run`,
  `uv_toolchain` + `UvToolchainInfo`, and the `pip` module
  extension. `bazel run //docs:update` regenerates; CI gates the
  committed copies via `diff_test`.
- GitHub Actions CI: `bazel test //...` on ubuntu + macos, plus a
  buildifier lint job.
- `CHANGELOG.md` (this file).

## 0.5.0 — cross-platform wheel `select()`

- `pip.parse(platforms = [<os>_<arch>, ...])` opts a hub into
  multi-platform mode. Packages with platform-divergent native
  wheels fan out into per-platform repos
  (`@<hub>__<pkg>__<platform>`) behind a selector repo that emits
  `alias(actual = select({...}))` over `@platforms//os` +
  `@platforms//cpu`. Non-host platform repos are declared but
  lazy-fetched.
- Pure-Python wheels stay single-repo (platform-agnostic). Sdist +
  git + path sources stay host-only, and the extension fails
  loudly if a multi-platform lockfile points at an sdist-only
  package (sdist install is host-only — running `uv pip install
  --target` once per requested platform is on the v0.6 roadmap).
- New `examples/multiplatform/` end-to-end fixture.
- Default `platforms = []` keeps v0.4 host-only behavior intact —
  zero behavior change for existing consumers.

## 0.4.0 — extras, markers, git/path sources

- **Extras**: `requirement("pkg[extra]")` resolves to a Bazel
  sub-target generated from each package's
  `[package.optional-dependencies]`. The extra re-exports `:pkg`
  plus the extra's filtered dep set.
- **Markers**: PEP 508 subset evaluator
  (`pip/private/markers.bzl`) — recursive-descent parser
  covering `==`/`!=`/`<`/`<=`/`>`/`>=`/`in`/`not in`,
  `and`/`or`/`not`, grouping. Evaluated at extension time
  against `python_version` + host; edges whose markers fail are
  filtered out.
- **Git sources** (`source = { git = "...", rev = "..." }`):
  fetched via `new_git_repository`.
- **Path sources** (`source = { path = "..." }`): symlinked via
  a thin `_path_repo` rule.
- **Editable sources**: explicit failure with a clear message.
- Hermetic uv invocation: `--no-config` on every `uv pip install`
  and `uv python install` call so the developer's
  `~/.config/uv/uv.toml` can't leak into sandbox builds.

## 0.3.0 — native wheel selection + sdist install via uv

- **Native wheel selection**
  (`pip/private/wheel_selection.bzl`,
  `pip/private/platform.bzl`): PEP 425/600 tag scoring against a
  host-specific ordered tag list. Picks the best
  `manylinux_*`/`macosx_*`-tagged wheel for the host.
- **Sdist install** (`pip/private/sdist_install.bzl`):
  `sdist_install_repo` repository_rule that downloads the sdist
  and shells to `@uv//:uv` (`uv pip install --target=. --no-deps`)
  at repo-rule time.
- New `pip.parse` attrs: `python_version` (`3.12` default, wheel
  tag matching) and `python` (`host` | `uv`, sdist install
  interpreter source).

## 0.2.0 — prebuilt-uv toolchain alternative

- `uv.toolchain(source = "prebuilt")` fetches the official
  astral-sh/uv release asset for the host platform from GitHub
  Releases. Skips the ~12-min source-build cold path.
- Supported hosts at pin: `darwin_{aarch64,x86_64}`,
  `linux_{aarch64,x86_64}`.
- `uv_toolchain.uv` now takes a `File` label
  (`allow_single_file = True`) so both `build` and `prebuilt`
  modes satisfy it via `@uv//:binary` uniformly. The `:install`
  rust_binary indirection is gone.

## 0.1.0 — initial release

- `@uv//:binary` built from astral-sh/uv source via rules_rust's
  `cargo_bootstrap_repository`.
- `uv_run` macro: sandbox-escaping `bazel run` wrapper.
- `pip.parse` module extension: `uv.lock` → `@pip` hub with
  per-package repos and a `requirement("<name>")` macro.
- Pure-Python wheel materialization (`py3-none-any`) +
  raw-sdist fallback (no build step).
- End-to-end smoke test in `examples/smoke/`.
