#!/usr/bin/env python3
"""Read a uv.lock TOML file from argv[1] and emit a JSON projection
that the @pip module extension can consume.

The output schema (intentionally narrow — only the bits the extension
needs to materialize one Bazel repo per package):

    {
      "requires_python": ">=3.10",                # may be empty
      "packages": [
        {
          "name": "requests",
          "version": "2.32.3",
          "source": "registry",                  # or "url" / "git" / "path"
          "dependencies": ["certifi", "idna", …],
          "wheels":   [{"url": "...", "sha256": "..."}, …],
          "sdist":    {"url": "...", "sha256": "..."}   # optional
        },
        …
      ]
    }

We deliberately drop fields rules_uv doesn't yet use (extras,
markers, resolution-markers, group). v0.2 can lift them in without
breaking the extension surface.

Why a script and not pure Starlark: uv.lock is TOML, and Starlark
has no TOML parser. Bazel's repo rules can shell out to the host
`python3`, and Python 3.11+'s stdlib `tomllib` covers parsing for
free.
"""

from __future__ import annotations

import json
import sys

try:
    import tomllib  # py 3.11+
except ModuleNotFoundError:
    sys.exit(
        "uvlock_to_json: requires Python 3.11+ (for stdlib tomllib). "
        "Found: " + sys.version
    )


def _hash(entry: dict) -> str | None:
    raw = entry.get("hash") or ""
    # uv.lock stores hashes as "sha256:<hex>"; strip the algorithm
    # prefix so the consumer can pass the bare hex to http_archive's
    # `sha256` attr.
    if raw.startswith("sha256:"):
        return raw[len("sha256:"):]
    return raw or None


def _source_kind(src: dict | None) -> str:
    if not src:
        return "unknown"
    if "registry" in src:
        return "registry"
    if "url" in src:
        return "url"
    if "git" in src:
        return "git"
    if "path" in src:
        return "path"
    if "editable" in src:
        return "editable"
    if "virtual" in src:
        return "virtual"
    return "unknown"


def project(lock: dict) -> dict:
    out_packages = []
    for pkg in lock.get("package", []):
        wheels = []
        for w in pkg.get("wheels", []):
            wheels.append({"url": w.get("url"), "sha256": _hash(w)})
        sdist = pkg.get("sdist")
        sdist_out = None
        if sdist:
            sdist_out = {"url": sdist.get("url"), "sha256": _hash(sdist)}
        deps = []
        for dep in pkg.get("dependencies", []):
            # Each dep is a table; we only carry the package name
            # for now — full marker/extra resolution is v0.2.
            if isinstance(dep, dict) and "name" in dep:
                deps.append(dep["name"])
        out_packages.append({
            "name": pkg.get("name", ""),
            "version": pkg.get("version", ""),
            "source": _source_kind(pkg.get("source")),
            "dependencies": deps,
            "wheels": wheels,
            "sdist": sdist_out,
        })
    return {
        "requires_python": lock.get("requires-python", ""),
        "packages": out_packages,
    }


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: uvlock_to_json.py <path/to/uv.lock>", file=sys.stderr)
        return 2
    with open(sys.argv[1], "rb") as f:
        lock = tomllib.load(f)
    json.dump(project(lock), sys.stdout, sort_keys=True, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
