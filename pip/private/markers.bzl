"""PEP 508 environment marker evaluator (deliberately scoped).

uv.lock dependency entries carry a `marker = "..."` field that
gates the edge on the install environment. Examples:

    python_full_version < '3.11'
    sys_platform == 'darwin'
    os_name == 'posix' and python_version >= '3.10'
    extra == 'security'

For v0.4 we evaluate markers at extension time against the
configured `python_version` + host platform — i.e., a single
host's view. If the marker is true we include the edge; if false
we drop it. Cross-platform `select()` is v0.5.

Implementation is a tiny recursive descent over the subset of PEP
508 that uv.lock actually emits. We support:

  * variables    `python_version`, `python_full_version`,
                 `os_name`, `sys_platform`, `platform_system`,
                 `platform_machine`, `extra`
  * literals     single- or double-quoted strings
  * comparisons  `==` `!=` `<` `<=` `>` `>=` `in` `not in`
  * booleans     `and` `or` `not`
  * grouping     `(...)`

Out of scope: PEP 440 version comparison nuances beyond plain
lexicographic (good enough for `3.11` vs `3.12`), arbitrary
right-hand-side expressions. The eval intentionally fails loud on
anything it can't parse so we notice unsupported markers instead
of silently dropping a dep.
"""

def eval_marker(marker_str, env):
    """Evaluate a marker expression against `env`.

    Args:
      marker_str: PEP 508 marker text. Empty string = no marker
        (unconditional edge), returns True.
      env: dict of marker variable → string value. Must contain
        keys for any variable the marker references.

    Returns:
      bool. Fails loudly on unsupported syntax.
    """
    if not marker_str:
        return True
    tokens = _tokenize(marker_str)
    result, consumed = _parse_or(tokens, 0, env, marker_str)
    if consumed != len(tokens):
        fail("rules_uv/markers: trailing tokens in '{}' (consumed {}/{}): {}".format(
            marker_str, consumed, len(tokens), tokens[consumed:],
        ))
    return result

def host_env(host_platform, python_version, extra = ""):
    """Build the marker environment for a host + interpreter.

    `host_platform` is canonical `<os>_<arch>` from `platform.bzl`.
    `python_version` is `"<major>.<minor>"`. `extra` is the active
    extra name when evaluating a dep that's gated on one (e.g.,
    `requests`'s `security` extra deps see `extra = "security"`).
    """
    parts = host_platform.split("_")
    os_name_ = parts[0]
    if os_name_ == "darwin":
        sys_platform = "darwin"
        platform_system = "Darwin"
        py_os_name = "posix"
    elif os_name_ == "linux":
        sys_platform = "linux"
        platform_system = "Linux"
        py_os_name = "posix"
    elif os_name_ == "windows":
        sys_platform = "win32"
        platform_system = "Windows"
        py_os_name = "nt"
    else:
        fail("rules_uv/markers: unsupported host_platform '{}'".format(host_platform))

    arch = parts[1] if len(parts) > 1 else ""
    if arch == "aarch64" and os_name_ == "darwin":
        platform_machine = "arm64"
    elif arch == "x86_64" and os_name_ == "darwin":
        platform_machine = "x86_64"
    elif arch == "aarch64":
        platform_machine = "aarch64"
    elif arch == "x86_64":
        platform_machine = "x86_64"
    else:
        platform_machine = arch

    # python_full_version follows `<major>.<minor>.<patch>`. Lockers
    # nearly always write markers in terms of the minor version (e.g.
    # `python_full_version < '3.11'` to mean "any 3.10.x"); pick
    # `.0` as the patch so `< '3.11'` evaluates the way humans
    # mean it for the configured minor.
    python_full_version = python_version + ".0"

    return {
        "python_version": python_version,
        "python_full_version": python_full_version,
        "os_name": py_os_name,
        "sys_platform": sys_platform,
        "platform_system": platform_system,
        "platform_machine": platform_machine,
        # PEP 508 also defines `implementation_name` (e.g. "cpython",
        # "pypy") and `platform_python_implementation` (the
        # title-cased form, "CPython", "PyPy"). We assume CPython —
        # rules_uv's toolchain story is CPython-only today (uv's
        # default Python is CPython; no rules_uv use case has
        # surfaced for PyPy). When markers like
        # `implementation_name == 'pypy'` show up in real lockfiles
        # (selectsmart-engine has them on greenlet etc.), they
        # evaluate to false and we drop those edges.
        "implementation_name": "cpython",
        "platform_python_implementation": "CPython",
        "extra": extra,
    }

# -----------------------------------------------------------------------------
# Tokenizer + parser. Kept intentionally small.
# -----------------------------------------------------------------------------

_KEYWORDS = ("and", "or", "not", "in")

def _tokenize(s):
    tokens = []
    i = 0
    n = len(s)
    for _ in range(n + 1):
        if i >= n:
            break
        c = s[i]
        if c == " " or c == "\t" or c == "\n":
            i += 1
            continue
        if c == "(" or c == ")":
            tokens.append(c)
            i += 1
            continue
        if c == "'" or c == "\"":
            j = i + 1
            for _ in range(n):
                if j >= n:
                    fail("rules_uv/markers: unterminated string starting at {}".format(i))
                if s[j] == c:
                    break
                j += 1
            tokens.append("STR:" + s[i + 1:j])
            i = j + 1
            continue
        # Two-char operators first.
        two = s[i:i + 2]
        if two in ("==", "!=", "<=", ">="):
            tokens.append(two)
            i += 2
            continue
        if c == "<" or c == ">":
            tokens.append(c)
            i += 1
            continue
        # Identifier or keyword.
        if c.isalpha() or c == "_":
            j = i
            for _ in range(n):
                if j >= n:
                    break
                cc = s[j]
                if cc.isalnum() or cc == "_":
                    j += 1
                else:
                    break
            tokens.append(s[i:j])
            i = j
            continue
        fail("rules_uv/markers: unexpected character '{}' at offset {} in '{}'".format(c, i, s))
    return tokens

def _peek(tokens, idx):
    return tokens[idx] if idx < len(tokens) else None

def _parse_or(tokens, idx, env, full):
    left, idx = _parse_and(tokens, idx, env, full)
    for _ in range(len(tokens)):
        if _peek(tokens, idx) != "or":
            break
        right, idx = _parse_and(tokens, idx + 1, env, full)
        left = left or right
    return left, idx

def _parse_and(tokens, idx, env, full):
    left, idx = _parse_not(tokens, idx, env, full)
    for _ in range(len(tokens)):
        if _peek(tokens, idx) != "and":
            break
        right, idx = _parse_not(tokens, idx + 1, env, full)
        left = left and right
    return left, idx

def _parse_not(tokens, idx, env, full):
    if _peek(tokens, idx) == "not":
        # Distinguish `not <expr>` from `not in` (which is handled
        # at the comparison level).
        if _peek(tokens, idx + 1) == "in":
            return _parse_cmp(tokens, idx, env, full)
        v, idx = _parse_not(tokens, idx + 1, env, full)
        return (not v), idx
    return _parse_cmp(tokens, idx, env, full)

def _parse_cmp(tokens, idx, env, full):
    left, idx = _parse_atom(tokens, idx, env, full)
    op = _peek(tokens, idx)
    if op in ("==", "!=", "<", "<=", ">", ">=", "in"):
        right, idx = _parse_atom(tokens, idx + 1, env, full)
        return _apply_cmp(left, op, right), idx
    if op == "not" and _peek(tokens, idx + 1) == "in":
        right, idx = _parse_atom(tokens, idx + 2, env, full)
        return _apply_cmp(left, "not in", right), idx
    return left, idx

def _parse_atom(tokens, idx, env, full):
    tok = _peek(tokens, idx)
    if tok == None:
        fail("rules_uv/markers: unexpected end of input in '{}'".format(full))
    if tok == "(":
        v, idx = _parse_or(tokens, idx + 1, env, full)
        if _peek(tokens, idx) != ")":
            fail("rules_uv/markers: missing ) in '{}'".format(full))
        return v, idx + 1
    if tok.startswith("STR:"):
        return tok[len("STR:"):], idx + 1
    # Bare identifier → look up in env. Unknown variables are an
    # error (silently treating them as "" would mask real lockfile
    # bugs in CI).
    if tok in env:
        return env[tok], idx + 1
    fail("rules_uv/markers: unknown variable or keyword '{}' in '{}'".format(tok, full))

def _apply_cmp(left, op, right):
    # All variable values are strings; comparisons follow Python's
    # PEP 508 semantics, which for our scope is plain string
    # comparison (works for python_version since "3.10" < "3.11"
    # lexicographically — note "3.10" < "3.9" is broken
    # lexicographically, but uv emits dotted version strings as
    # written by the resolver, which already pads sensibly for
    # the comparisons we encounter).
    if op == "==":
        return left == right
    if op == "!=":
        return left != right
    if op == "<":
        return _version_lt(left, right)
    if op == "<=":
        return _version_lt(left, right) or left == right
    if op == ">":
        return _version_lt(right, left)
    if op == ">=":
        return _version_lt(right, left) or left == right
    if op == "in":
        return right.find(left) >= 0
    if op == "not in":
        return right.find(left) < 0
    fail("rules_uv/markers: unhandled comparison op '{}'".format(op))

def _version_lt(a, b):
    """Compare two dotted version strings numerically component-wise.

    Falls back to string comparison for non-numeric components
    (e.g., release tags). This is sufficient for the
    python_version / python_full_version comparisons we encounter.
    """
    a_parts = a.split(".")
    b_parts = b.split(".")
    for i in range(max(len(a_parts), len(b_parts))):
        ai = a_parts[i] if i < len(a_parts) else "0"
        bi = b_parts[i] if i < len(b_parts) else "0"
        if ai.isdigit() and bi.isdigit():
            an = int(ai)
            bn = int(bi)
            if an != bn:
                return an < bn
        else:
            if ai != bi:
                return ai < bi
    return False
