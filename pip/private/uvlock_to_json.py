#!/usr/bin/env python3
"""Read a uv.lock TOML file from argv[1] and emit a JSON projection
that the @pip module extension can consume.

The output schema is narrow but stable — the extension imports the
keys verbatim, so any change here is a coordinated change to
`pip/extensions.bzl`.

    {
      "requires_python": ">=3.10",
      "dependency_groups": {
        # PEP 735 dependency groups (uv records them under the
        # workspace-root editable entry's `dev-dependencies` table —
        # the key is misleading; it holds ALL groups, not just
        # `dev`). We collapse them to a top-level map: group name →
        # list of dep edges (name, marker, extras).
        "dev":  [{"name": "pytest", "marker": "", "extras": []}],
        "docs": [{"name": "sphinx", "marker": "", "extras": []}],
      },
      "packages": [
        {
          "name": "requests",
          "version": "2.32.3",
          "source": {
            "kind": "registry" | "url" | "git" | "path" | "editable" | "virtual" | "unknown",
            "url":  "...",          # registry/url only
            "git":  "...",          # git only
            "rev":  "<sha>",        # git only
            "path": "...",          # path/editable only
          },
          "dependencies": [
            {"name": "certifi", "marker": "", "extras": []},
            # `extras` is a list because a dep edge can request
            # multiple extras of the target: { name = "httpx",
            # extra = ["http2", "socks"] } in uv.lock.
            {"name": "httpx",   "marker": "", "extras": ["http2"]},
            ...
          ],
          "optional_dependencies": {
            # Extra name → list of base package names that get
            # pulled in when the extra is requested.
            "security": ["pyOpenSSL", "cryptography"],
          },
          "wheels":   [{"url": "...", "sha256": "..."}, ...],
          "sdist":    {"url": "...", "sha256": "..."} | null,
        },
        ...
      ]
    }

We deliberately drop fields rules_uv doesn't yet use (build
constraints, conflicting groups). Resolution-markers ARE projected
(v0.7.3+) — when a lockfile has multiple entries with the same
package name gated on different Python versions, the extension
filters them at materialize time so only the env-matching variant
wins.

Why a script and not pure Starlark: uv.lock is TOML, and Starlark
has no TOML parser. Bazel's repo rules can shell out to the host
`python3`, and Python 3.11+'s stdlib `tomllib` covers parsing.
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


def _strip_hash(entry: dict) -> str | None:
    raw = entry.get("hash") or ""
    if raw.startswith("sha256:"):
        return raw[len("sha256:"):]
    return raw or None


def _source(src: dict | None) -> dict:
    """Normalize the `[package.source]` table into a fixed shape."""
    if not src:
        return {"kind": "unknown"}
    if "registry" in src:
        return {"kind": "registry", "url": src["registry"]}
    if "url" in src:
        return {"kind": "url", "url": src["url"]}
    if "git" in src:
        # uv records a full git URL plus a `rev = "<sha>"` query
        # string or a separate `rev` field. We keep both keys for
        # the extension to dispatch on.
        return {
            "kind": "git",
            "git": src.get("git", ""),
            "rev": src.get("rev", ""),
        }
    if "path" in src:
        return {"kind": "path", "path": src["path"]}
    if "editable" in src:
        return {"kind": "editable", "path": src["editable"]}
    if "virtual" in src:
        return {"kind": "virtual"}
    return {"kind": "unknown"}


def _dep(raw: dict) -> dict:
    """Project a single dependency entry, including marker + extras."""
    # uv writes `extra = ["http2"]` for "this edge requests pkg[http2]".
    # We carry the list verbatim so the extension can re-emit
    # the right per-extra dep labels.
    extras = raw.get("extra") or []
    if isinstance(extras, str):  # defensive: tolerate older schemas
        extras = [extras] if extras else []
    return {
        "name": raw.get("name", ""),
        "marker": raw.get("marker", ""),
        "extras": list(extras),
    }


def _extras(pkg: dict) -> dict:
    """`optional-dependencies` is a TOML table keyed by extra name.

    Each value is a list of dependency tables. We collapse to a
    `{extra: [pkg_name, ...]}` mapping; per-edge markers/extras
    inside an extra are dropped for v0.4 (revisit when a real
    consumer needs nested marker semantics).
    """
    opt = pkg.get("optional-dependencies") or {}
    out = {}
    for name, deps in opt.items():
        out[name] = [d.get("name", "") for d in deps if isinstance(d, dict)]
    return out


def _dependency_groups(lock: dict) -> dict:
    """Hoist PEP 735 dependency groups to a top-level map.

    uv attaches them to whichever package entry represents the
    workspace root (typically `source = { editable = "." }` or
    `source = { virtual = "." }`). The TOML key is
    `dev-dependencies`, which is misleading — it carries every
    named group (`dev`, `test`, `docs`, …), not just `dev`. We
    look for the editable/virtual entry and pick that up.
    """
    out: dict = {}
    for pkg in lock.get("package", []):
        src = pkg.get("source") or {}
        if "editable" not in src and "virtual" not in src:
            continue
        groups = pkg.get("dev-dependencies") or {}
        for name, entries in groups.items():
            out[name] = [_dep(d) for d in entries if isinstance(d, dict)]
    return out


def project(lock: dict) -> dict:
    out_packages = []
    for pkg in lock.get("package", []):
        wheels = [
            {"url": w.get("url"), "sha256": _strip_hash(w)}
            for w in pkg.get("wheels", [])
        ]
        sdist = pkg.get("sdist")
        sdist_out = (
            {"url": sdist.get("url"), "sha256": _strip_hash(sdist)}
            if sdist
            else None
        )
        deps = [_dep(d) for d in pkg.get("dependencies", []) if isinstance(d, dict)]
        out_packages.append({
            "name": pkg.get("name", ""),
            "version": pkg.get("version", ""),
            "source": _source(pkg.get("source")),
            "dependencies": deps,
            "optional_dependencies": _extras(pkg),
            "wheels": wheels,
            "sdist": sdist_out,
            # uv writes a `resolution-markers` array on package
            # entries that only apply to a subset of resolution
            # envs (most commonly per-Python-version variants).
            # If the list is non-empty, ANY marker passing for the
            # host means the entry is in-scope.
            "resolution_markers": list(pkg.get("resolution-markers") or []),
        })
    return {
        "requires_python": lock.get("requires-python", ""),
        "dependency_groups": _dependency_groups(lock),
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
