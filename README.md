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

## Status: v0.4

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
* End-to-end smoke test (`examples/smoke/`) — `py_test` that imports
  idna (pure wheel), markupsafe (native wheel), iniconfig (sdist
  install), and uses `certifi[bundle]` (per-extra target). The lockfile
  also includes a marker-gated edge that's correctly dropped.

Deferred to v0.5 (see [`docs/ROADMAP.md`](docs/ROADMAP.md)):

* Cross-platform wheels via `select()` for multi-target builds.
* Migration to rules_python's `uv_toolchain` once it leaves
  experimental.

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
common --registry=https://raw.githubusercontent.com/fastverk/bazel-registry/main/
common --registry=https://bcr.bazel.build/
```

`MODULE.bazel`:

```python
bazel_dep(name = "rules_uv", version = "0.4.0")
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
