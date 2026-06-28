# rules_uv

Bazel rules for [`uv`](https://github.com/astral-sh/uv), Astral's
high-speed Python package + project manager. Two pieces:

1. **`@uv//:binary`** — the uv CLI, built from source inside Bazel
   via `rules_rust`'s `cargo_bootstrap_repository` (so the binary is
   pinned to the same Rust toolchain + uv source revision across
   every machine in the org).

2. **`@rules_uv//pip:pip.parse`** — a `uv.lock` → `@pip` module
   extension. Same shape as rules_python's `pip_parse`, but driven
   by uv's resolver output: one Bazel-fetched repo per package, an
   aggregating hub repo with a `requirement("<name>")` macro, and
   transitive deps wired up by the lockfile.

## Status: v0.7

What v0.7 adds on top of v0.6:

- **Editable workspace roots** — `uv.lock` entries with
  `source = { editable = "." }` (uv's standard pattern for a
  workspace's own project) are now skipped rather than rejected.
  Their attached `dev-dependencies` table is mined for PEP 735
  dependency groups.
- **PEP 735 dependency groups** — new `group(name)` macro in the
  hub's `requirements.bzl` returns labels for every package in a
  named group. Markers + extras per edge are honoured.

```python
load("@pip//:requirements.bzl", "requirement", "group")

py_test(
    name = "tests",
    deps = [requirement("my_lib")] + group("dev"),
)
```



What ships:

* `uv` binary, two interchangeable paths:
  - `source = "build"` (default) — built from astral-sh/uv source
    via rules_rust's `cargo_bootstrap_repository`. ~12-min cold
    build; cached after. Highest hermeticity.
  - `source = "prebuilt"` — fetches the official release asset
    for the host platform (`darwin_aarch64`, `darwin_x86_64`,
    `linux_aarch64`, `linux_x86_64`). Seconds to fetch.
* `pip.parse` reads `uv.lock` and materializes:
  - **Pure-Python wheels** (`py3-none-any`) — http_archive unpacks
    the wheel as a zip.
  - **Native wheels** (`manylinux_*`, `macosx_*_arm64`, …) —
    PEP 425 / PEP 600 tag scoring against the host triple +
    `python_version`. Best-matching wheel wins.
  - **Sdists** — shells to `@uv//:uv` (`uv pip install --target=. --no-deps`)
    at repo-rule time. Builds C extensions if the sdist has any.
    Choose between `python = "host"` (uses `python3` on PATH) and
    `python = "uv"` (uses `uv python install <version>`).
  - **Git sources** (`source = { git = "…", rev = "…" }`) — fetched
    via `new_git_repository` with the BUILD wrapper.
  - **Path sources** (`source = { path = "…" }`) — symlinked into
    a Bazel repo via a thin `new_local_repository`-shaped rule.
  - **Editable sources** — explicitly rejected with a clear error.
* **Extras** (`requirement("pkg[extra]")`) — per-extra Bazel sub-targets
  generated from each package's `[package.optional-dependencies]`
  table. The extra target re-exports `:pkg` plus the extra's deps.
* **Markers** (`marker = "python_full_version < '3.11'"`, etc.) —
  evaluated at extension time against the configured `python_version`
  + host platform. Edges whose markers fail are filtered out. PEP
  508 subset: `python_version`, `python_full_version`, `os_name`,
  `sys_platform`, `platform_system`, `platform_machine`, `extra`;
  comparisons + `and`/`or`/`not`/`in`/`not in`/grouping.
* **Cross-platform wheels + pure-Python sdists** (`pip.parse(platforms = [...])`)
  — when the consumer opts into multi-platform mode:
  - Packages with platform-divergent native wheels fan out into
    per-platform repos behind a selector that
    `alias`-`select()`s on `@platforms//os` + `@platforms//cpu`.
  - Pure-Python wheels stay single-repo.
  - **Pure-Python sdists** (v0.6) install once on the host with a
    native-extension check; pure-Python results become a single
    repo serving every target platform. Sdists that build native
    code still fail loudly (cross-arch reuse of a host-built
    `.so`/`.dylib`/`.pyd` is unsafe).
  - Git + path sources remain host-only and fail loudly under a
    cross-platform build.
* End-to-end smoke tests:
  - `examples/smoke/` — host-only build with all five lockfile-feature
    paths: pure wheel, native wheel, sdist install, `certifi[bundle]`
    extra, marker-gated dep filtered out.
  - `examples/multiplatform/` — multi-platform lockfile + py_test
    that resolves a native wheel through the per-platform selector.

Deferred to v0.7+ (see [`docs/ROADMAP.md`](docs/ROADMAP.md)):

* Migration to rules_python's `uv_toolchain` once it leaves
  experimental.
* Native-extension sdists in multi-platform mode (cross-compile).
* musl + Windows platform tag tables in `pip/private/platform.bzl`.

## Architecture

```
//uv                       uv binary + toolchain
  defs.bzl                 user-facing rule: uv_run
  toolchains.bzl           uv_toolchain rule
  extensions.bzl           module extension: fetch source + cargo_bootstrap
  private/known_versions.bzl  pinned uv versions + sha256s

//pip                      uv.lock → @pip
  extensions.bzl           module extension: pip.parse
  private/uvlock_to_json.py  TOML → JSON shim (uses py 3.11 stdlib)
  private/wheel_selection.bzl  pure-wheel-first artifact picker
  private/pip_package.BUILD.tpl  per-package BUILD template

//examples/smoke           end-to-end smoke test
```

## Install

`.bazelrc`:

```
common --registry=https://registry.fastverk.com/
common --registry=https://bcr.bazel.build/
```

`MODULE.bazel`:

```python
bazel_dep(name = "rules_uv", version = "0.5.0")
bazel_dep(name = "rules_python", version = "1.7.0")

uv = use_extension("@rules_uv//uv:extensions.bzl", "uv")
# Optional — omit the tag for the default `source = "build"` path.
uv.toolchain(source = "prebuilt")
use_repo(uv, "uv", "uv_source")
register_toolchains("@rules_uv//uv:uv_toolchain_def")

pip = use_extension("@rules_uv//pip:extensions.bzl", "pip")
pip.parse(
    hub_name = "pip",
    lock = "//:uv.lock",
    python_version = "3.12",   # used for wheel tag matching
    python = "host",           # "host" (python3 on PATH) | "uv"
)
use_repo(pip, "pip")
```

## `pip.parse`

In a BUILD file:

```python
load("@pip//:requirements.bzl", "requirement")
load("@rules_python//python:defs.bzl", "py_library")

py_library(
    name = "app",
    srcs = ["app.py"],
    deps = [
        requirement("idna"),
        requirement("certifi"),
    ],
)
```

`requirement(name)` is case-insensitive and accepts the same
spellings PyPI does (`_`, `-`, `.` are folded together per PEP 503).

## `uv_run`

`bazel run`-able wrapper around `uv <subcommand>` against the live
workspace source (escapes the sandbox so `uv lock`, `uv pip sync`,
etc. can write into the user's tree):

```python
load("@rules_uv//uv:defs.bzl", "uv_run")

uv_run(
    name = "lock",
    subcommand = "lock",
)

uv_run(
    name = "sync",
    subcommand = "pip",
    args = ["sync", "requirements.txt"],
)
```

```sh
bazel run //:lock
bazel run //:sync -- --refresh
```

## Versioning

`rules_uv` versions track its own surface, not uv's. The pinned uv
version lives in [`uv/private/known_versions.bzl`](uv/private/known_versions.bzl);
override with `uv.toolchain(version = "<new>")` in your MODULE.bazel.
