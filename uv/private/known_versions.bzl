"""Pinned uv versions for the `uv` module extension.

Two parallel pin tables, keyed by version string:

  * `KNOWN_VERSIONS` (str → str)
    sha256 of the GitHub source tarball, consumed by the `build`
    path (`cargo_bootstrap_repository`).

  * `KNOWN_PREBUILT_SHAS` (str → str → str)
    nested mapping: version → canonical host platform → sha256 of
    the official prebuilt release asset, consumed by the `prebuilt`
    path. Each inner key is one of the canonical platform names
    listed in `PREBUILT_PLATFORMS` below.

Add a new version: drop sha256 entries into both tables. The hashes
can be lifted verbatim from
`https://github.com/astral-sh/uv/releases/download/<v>/sha256.sum`.
"""

DEFAULT_VERSION = "0.11.15"

URL_TEMPLATE = "https://github.com/astral-sh/uv/archive/refs/tags/{version}.tar.gz"

# Map canonical "<os>_<arch>" → the uv-release-asset triple. uv's
# release naming uses Rust target triples, so we keep both
# directions on hand: the canonical name is what callers detect
# from `mctx.os.name` / `mctx.os.arch`; the triple is what the
# asset filename actually contains.
PREBUILT_PLATFORMS = {
    "darwin_aarch64": "aarch64-apple-darwin",
    "darwin_x86_64": "x86_64-apple-darwin",
    "linux_aarch64": "aarch64-unknown-linux-gnu",
    "linux_x86_64": "x86_64-unknown-linux-gnu",
    # musl / windows / 32-bit triples are intentionally omitted
    # until someone needs them — pinning shas we never test is
    # security theater.
}

PREBUILT_URL_TEMPLATE = (
    "https://github.com/astral-sh/uv/releases/download/{version}/" +
    "uv-{triple}.tar.gz"
)

KNOWN_VERSIONS = {
    "0.11.15": "78d3070b6add2d8f5a28d5781c938b75d2e861736cfe6bf7a88757c395f10a2e",
}

# Lifted from
# https://github.com/astral-sh/uv/releases/download/0.11.15/sha256.sum.
KNOWN_PREBUILT_SHAS = {
    "0.11.15": {
        "darwin_aarch64": "7e5b336108f8576eda1939920ca0a805b4a9a3c3d3eb2f6140e38b7092fbe4f3",
        "darwin_x86_64": "42bca7cc879d117ed7139a0e26de8cab0b6f033ad439a32144f324d1f8580d8c",
        "linux_aarch64": "21a7dd1a03ea17ac0366887455dab15d215b31dba0870dcd65d3714e22f46c81",
        "linux_x86_64": "b03e572f010bea94a4a52d42671ba72981e12894f71576181a1d26ff68546da7",
    },
}
