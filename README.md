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

## Status: v0.1

What ships:

* `uv` is built from source. ~12-minute cold build; cached after.
* `pip.parse` reads `uv.lock` and materializes pure-Python packages
  (the `py3-none-any` wheel slice) into Bazel. Sdists fall back to a
  raw download; consumers can wire them through their own builders.
* End-to-end smoke test (`examples/smoke/`) — `py_test` that imports
  `idna` + `certifi` resolved through the extension.

Deferred to v0.2 (see [`docs/ROADMAP.md`](docs/ROADMAP.md)):

* Native-wheel selection (`manylinux_*`, `macosx_*_arm64`, …). Today
  we ship only the pure-Python slice; native wheels need real PEP
  425 / PEP 600 tag matching.
* Optional-dependency groups + per-marker resolution.
* Git + path + editable lockfile sources.
* Prebuilt-uv toolchain alternative (skip the 12-minute cold build
  when you're OK with Astral's GitHub-Release binaries).

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
bazel_dep(name = "rules_uv", version = "0.1.0")
bazel_dep(name = "rules_python", version = "1.7.0")

uv = use_extension("@rules_uv//uv:extensions.bzl", "uv")
use_repo(uv, "uv", "uv_source")
register_toolchains("@rules_uv//uv:uv_toolchain_def")

pip = use_extension("@rules_uv//pip:extensions.bzl", "pip")
pip.parse(
    hub_name = "pip",
    lock = "//:uv.lock",
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
