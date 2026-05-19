"""Pick the best artifact (wheel or sdist) for a package + host.

PEP 425 / PEP 600 tag matching, kept *narrow* relative to rules_python:
we score on (platform, abi, python) priority and return the wheel
whose tag triple has the lowest total rank. Wheel filenames look
like:

    <name>-<version>(-<build>)?-<py>-<abi>-<plat>.whl

Each of the three tag fields may be `.`-separated (a single wheel
can declare compatibility with multiple Python versions, ABIs, or
platforms). For each field we expand and pick the best match
against the host's ordered tag list; if any field has no match,
the wheel is skipped.
"""

load(":platform.bzl", "platform_tags", "python_tags")

def _parse_wheel_filename(filename):
    """Returns struct(py_tags, abi_tags, platform_tags) or None.

    `filename` is the basename of the wheel URL, e.g.
    `cryptography-44.0.0-cp39-abi3-manylinux_2_28_x86_64.whl`.
    """
    if not filename.endswith(".whl"):
        return None
    stem = filename[:-len(".whl")]
    parts = stem.split("-")
    # Wheel filenames have 5 or 6 hyphen-delimited components:
    #   name-version[-build]-py-abi-plat
    # We need just the last three. Slicing from the right is safe
    # even when `name` itself contains hyphens.
    if len(parts) < 5:
        return None
    return struct(
        py_tags = parts[-3].split("."),
        abi_tags = parts[-2].split("."),
        platform_tags = parts[-1].split("."),
    )

def _score_tag(wheel_tags, host_tags):
    """Lowest index of any host tag that any wheel tag matches.

    Returns -1 if no match (caller treats as "incompatible").
    """
    best = -1
    for wt in wheel_tags:
        for i, ht in enumerate(host_tags):
            if wt == ht:
                if best == -1 or i < best:
                    best = i
                break
    return best

def select_artifact(pkg, host_platform, python_version):
    """Pick the best wheel (or sdist fallback) for `pkg` on host.

    Args:
      pkg: dict from `uvlock_to_json` projection (`wheels`, `sdist`,
        `name`, …).
      host_platform: canonical `<os>_<arch>` (see `platform.bzl`).
      python_version: `"<major>.<minor>"` for tag matching.

    Returns:
      struct(kind, url, sha256, filename) with kind in
      {"wheel", "sdist"}. Fails if neither matches.
    """
    host_plat_tags = platform_tags(host_platform)
    host_pytags = python_tags(python_version)

    # Lower combined score = better. Score is a tuple
    # (platform_rank, abi_rank, py_rank); compare lexicographically
    # since platform specificity dominates Python tag specificity
    # in real-world wheel lookups.
    best = None
    best_score = None
    for wheel in pkg.get("wheels", []):
        url = wheel.get("url") or ""
        filename = url.rsplit("/", 1)[-1]
        tags = _parse_wheel_filename(filename)
        if tags == None:
            continue

        plat_rank = _score_tag(tags.platform_tags, host_plat_tags)
        if plat_rank < 0:
            continue
        abi_rank = _score_tag(tags.abi_tags, host_pytags.abi)
        if abi_rank < 0:
            continue
        py_rank = _score_tag(tags.py_tags, host_pytags.py)
        if py_rank < 0:
            continue

        score = (plat_rank, abi_rank, py_rank)
        if best_score == None or score < best_score:
            best_score = score
            best = struct(
                kind = "wheel",
                url = url,
                sha256 = wheel.get("sha256") or "",
                filename = filename,
            )

    if best != None:
        return best

    sdist = pkg.get("sdist")
    if sdist and sdist.get("url"):
        return struct(
            kind = "sdist",
            url = sdist["url"],
            sha256 = sdist.get("sha256") or "",
            filename = sdist["url"].rsplit("/", 1)[-1],
        )

    fail(
        "rules_uv/pip: package {!r} has no wheel matching host={} " +
        "python={} and no sdist. The lockfile must include either a " +
        "compatible wheel or an sdist.".format(
            pkg.get("name", "<unnamed>"),
            host_platform,
            python_version,
        ),
    )
