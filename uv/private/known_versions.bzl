"""Pinned uv versions for `cargo_bootstrap_repository`.

`URL_TEMPLATE` is filled in with `{version}` to produce a stable
astral-sh/uv source tarball URL. `KNOWN_VERSIONS` maps a uv version
to its source-tarball sha256.

Add a new version by computing the sha256 of the tarball at
`https://github.com/astral-sh/uv/archive/refs/tags/<version>.tar.gz`
and dropping a new entry here.
"""

DEFAULT_VERSION = "0.11.15"

URL_TEMPLATE = "https://github.com/astral-sh/uv/archive/refs/tags/{version}.tar.gz"

# Each value is the sha256 of the gzipped source tarball above. The
# "uv-<version>" prefix that GitHub adds is stripped when unpacking
# (see extensions.bzl).
KNOWN_VERSIONS = {
    "0.11.15": "78d3070b6add2d8f5a28d5781c938b75d2e861736cfe6bf7a88757c395f10a2e",
}
