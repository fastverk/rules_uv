"""Host-platform detection + PEP 425 / PEP 600 tag enumeration.

Used by `wheel_selection.bzl` to score wheel candidates and by the
sdist_install repo rule to pick the right Python interpreter
identity. The data here is *intentionally narrow* — we ship the
tag set for the four hosts that fastverk actually targets and let
new ones grow on demand. rules_python proper has a much more
elaborate tag-matching surface; matching their breadth is a v0.4+
ambition.

Conventions:

  * Canonical platform name: `<os>_<arch>` (e.g. `darwin_aarch64`).
    Same shape as `uv/private/known_versions.bzl#PREBUILT_PLATFORMS`.

  * Platform tag list: ordered most-specific first. The first
    matching wheel for a given (py, abi, platform) wins.

  * `none` ABI and `any` platform appear once at the end of the
    respective lists so pure-python wheels still match as a last
    resort.
"""

def host_platform(rctx_or_mctx):
    """Return canonical `<os>_<arch>` for the host running Bazel.

    Accepts either a `repository_ctx` or `module_ctx` — both expose
    `.os.name` and `.os.arch`.
    """
    os_name = rctx_or_mctx.os.name.lower()
    arch = rctx_or_mctx.os.arch.lower()
    if "mac os" in os_name or "darwin" in os_name:
        os_canonical = "darwin"
    elif "linux" in os_name:
        os_canonical = "linux"
    elif "windows" in os_name:
        os_canonical = "windows"
    else:
        fail("rules_uv: unsupported host OS: {}".format(rctx_or_mctx.os.name))

    if arch in ("aarch64", "arm64"):
        arch_canonical = "aarch64"
    elif arch in ("x86_64", "amd64"):
        arch_canonical = "x86_64"
    else:
        fail("rules_uv: unsupported host arch: {}".format(rctx_or_mctx.os.arch))

    return "{}_{}".format(os_canonical, arch_canonical)

# Platform-tag table, in priority order. Tags follow PEP 425/600
# naming. `manylinux_2_17` = `manylinux2014`; we list both spellings
# because publishers tag inconsistently.
_PLATFORM_TAGS = {
    "linux_x86_64": [
        "manylinux_2_39_x86_64",
        "manylinux_2_38_x86_64",
        "manylinux_2_36_x86_64",
        "manylinux_2_34_x86_64",
        "manylinux_2_31_x86_64",
        "manylinux_2_28_x86_64",
        "manylinux_2_27_x86_64",
        "manylinux_2_24_x86_64",
        "manylinux_2_17_x86_64",
        "manylinux2014_x86_64",
        "manylinux2010_x86_64",
        "manylinux1_x86_64",
        "linux_x86_64",
    ],
    "linux_aarch64": [
        "manylinux_2_39_aarch64",
        "manylinux_2_38_aarch64",
        "manylinux_2_34_aarch64",
        "manylinux_2_31_aarch64",
        "manylinux_2_28_aarch64",
        "manylinux_2_27_aarch64",
        "manylinux_2_17_aarch64",
        "manylinux2014_aarch64",
        "linux_aarch64",
    ],
    "darwin_aarch64": [
        # macOS x.y wheels are backward-compatible: a macosx_11_0
        # wheel runs on macOS 12+. We over-include here and let the
        # priority order pick the highest match.
        "macosx_15_0_arm64",
        "macosx_14_0_arm64",
        "macosx_13_0_arm64",
        "macosx_12_0_arm64",
        "macosx_11_0_arm64",
        "macosx_15_0_universal2",
        "macosx_14_0_universal2",
        "macosx_13_0_universal2",
        "macosx_12_0_universal2",
        "macosx_11_0_universal2",
        "macosx_10_16_universal2",
        "macosx_10_15_universal2",
        "macosx_10_14_universal2",
        "macosx_10_13_universal2",
        "macosx_10_12_universal2",
        "macosx_10_9_universal2",
    ],
    "darwin_x86_64": [
        "macosx_15_0_x86_64",
        "macosx_14_0_x86_64",
        "macosx_13_0_x86_64",
        "macosx_12_0_x86_64",
        "macosx_11_0_x86_64",
        "macosx_10_16_x86_64",
        "macosx_10_15_x86_64",
        "macosx_10_14_x86_64",
        "macosx_10_13_x86_64",
        "macosx_10_12_x86_64",
        "macosx_10_9_x86_64",
        "macosx_15_0_universal2",
        "macosx_14_0_universal2",
        "macosx_13_0_universal2",
        "macosx_12_0_universal2",
        "macosx_11_0_universal2",
        "macosx_10_16_universal2",
        "macosx_10_15_universal2",
        "macosx_10_14_universal2",
        "macosx_10_13_universal2",
        "macosx_10_12_universal2",
        "macosx_10_9_universal2",
    ],
}

def platform_tags(canonical):
    """Ordered list of platform tags compatible with `canonical`.

    Always ends with `any` so a pure-python wheel matches.
    """
    tags = _PLATFORM_TAGS.get(canonical)
    if tags == None:
        fail(
            "rules_uv/pip: no platform-tag table for {}. " +
            "Supported: {}. Add an entry to _PLATFORM_TAGS in " +
            "platform.bzl to fix.".format(canonical, sorted(_PLATFORM_TAGS.keys())),
        )
    return tags + ["any"]

def python_tags(python_version):
    """Compatible (py_tag list, abi_tag list) for an interpreter.

    `python_version` is `"<major>.<minor>"` (e.g. `"3.12"`).

    Returns:
        struct(py = [...], abi = [...])

    Py tag priority: cpython-specific (cp310) > major.minor py
    (py310) > major py (py3) > pure (none). ABI priority:
    cp310 > abi3 > none.
    """
    major, minor = python_version.split(".")
    return struct(
        py = [
            "cp{}{}".format(major, minor),
            "py{}{}".format(major, minor),
            "py{}".format(major),
            "none",
        ],
        abi = [
            "cp{}{}".format(major, minor),
            "abi3",
            "none",
        ],
    )
