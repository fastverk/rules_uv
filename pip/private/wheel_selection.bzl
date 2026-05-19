"""Pick the wheel (or sdist fallback) to materialize per package.

The full PEP 425 / PEP 600 tag-matching algorithm is large and
platform-dependent (see rules_python's `whl_target_platforms.bzl`
for the canonical implementation, ~600 lines). For v0.1 we use a
simpler heuristic that covers the >80% case:

  1. Prefer a pure-Python wheel (`py3-none-any.whl` / `py2.py3-none-any`).
     Pure wheels are byte-identical across platforms, so this gives
     us hermetic, reproducible builds.
  2. Otherwise fall back to the sdist. Sdists are also platform-
     independent; downstream consumers (or rules_python proper) can
     build them against a real interpreter.
  3. If neither exists, fail with a diagnostic.

Native-wheel selection (manylinux / macosx_*_arm64 / win_amd64) is
deferred to v0.2, which will require either bind-mounting the host
triple into the repo rule or shelling to uv itself (`uv pip
install --target=`) for the resolution step.
"""

_PURE_WHEEL_SUFFIXES = (
    "-py3-none-any.whl",
    "-py2.py3-none-any.whl",
    "-py3-none-any.whl",
)

def _is_pure_wheel(url):
    if not url:
        return False
    tail = url.rsplit("/", 1)[-1]
    for suffix in _PURE_WHEEL_SUFFIXES:
        if tail.endswith(suffix):
            return True
    return False

def select_artifact(pkg):
    """Pick the artifact for `pkg` (from uvlock_to_json's projection).

    Returns a struct(kind, url, sha256, filename) where kind is one
    of "wheel" or "sdist".
    """
    for wheel in pkg.get("wheels", []):
        if _is_pure_wheel(wheel.get("url")):
            return struct(
                kind = "wheel",
                url = wheel["url"],
                sha256 = wheel.get("sha256") or "",
                filename = wheel["url"].rsplit("/", 1)[-1],
            )
    sdist = pkg.get("sdist")
    if sdist and sdist.get("url"):
        return struct(
            kind = "sdist",
            url = sdist["url"],
            sha256 = sdist.get("sha256") or "",
            filename = sdist["url"].rsplit("/", 1)[-1],
        )
    fail(
        "rules_uv/pip: package {} has no pure-python wheel and no sdist. " +
        "Native wheel selection is not yet implemented (v0.2).".format(
            pkg.get("name", "<unnamed>"),
        ),
    )
