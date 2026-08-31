#!/usr/bin/env python3
"""Verify FFI call signatures against the C header declarations.

The last unmeasured surface. A binding can resolve, be implemented, and have
correct struct layouts, and still be wrong: `call["wgpuFoo"](a, b)` against a
three-parameter C function compiles, links, and corrupts the call. Nothing
else in the gate set can see it.

Checks each `self._wgpu.call["wgpuX", Ret?](args...)` in the loader against the
header declaration:

  * arity      — argument count must equal the C parameter count
  * void-ness  — a call with no return-type parameter must target a `void`
                 function, and one with a return type must not

Argument *types* are not compared. Doing that needs a Mojo-type -> C-type map
that would itself need maintaining, and the two checks here already catch the
failure modes that silently corrupt a call.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOADER = os.path.join(ROOT, "wgpu/_backend/wgpu_native/loader.mojo")
HEADERS = [os.path.join(ROOT, "ffi/include/webgpu/webgpu.h"),
           os.path.join(ROOT, "ffi/include/webgpu/wgpu.h")]


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def split_top_level(s):
    """Split on commas not nested in (), [] or <>."""
    out, depth, cur = [], 0, ""
    for ch in s:
        if ch in "([<":
            depth += 1
        elif ch in ")]>":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return [x.strip() for x in out if x.strip()]


def balanced(src, i):
    """Given index of '(', return (inner_text, index_after_close)."""
    assert src[i] == "("
    depth = 0
    for j in range(i, len(src)):
        if src[j] == "(":
            depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                return src[i + 1:j], j + 1
    raise ValueError("unbalanced")


def header_decls():
    """symbol -> (return_type, param_count)."""
    text = "".join(read(h) for h in HEADERS)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    decls = {}
    for m in re.finditer(r"\b((?:const\s+)?[A-Za-z_][\w]*\s*\**)\s*\b(wgpu[A-Z]\w*)\s*\(", text):
        ret, name = m.group(1).strip(), m.group(2)
        try:
            inner, _ = balanced(text, m.end() - 1)
        except ValueError:
            continue
        params = split_top_level(inner)
        if len(params) == 1 and params[0].replace(" ", "") == "void":
            params = []
        # a later declaration of the same symbol should agree; keep the first
        decls.setdefault(name, (ret, len(params)))
    return decls


def loader_calls():
    """(symbol, has_return, argc, line) for each _wgpu.call site."""
    src = read(LOADER)
    out = []
    for m in re.finditer(r'self\._wgpu\.call\[\s*"(\w+)"\s*(,)?', src):
        sym, comma = m.group(1), m.group(2)
        close = src.index("]", m.end())
        has_ret = comma is not None
        i = src.index("(", close)
        inner, _ = balanced(src, i)
        argc = len(split_top_level(inner))
        line = src.count("\n", 0, m.start()) + 1
        out.append((sym, has_ret, argc, line))
    return out


def main():
    decls, calls = header_decls(), loader_calls()
    if not calls:
        print("check-signatures: parsed no call sites — parser broken?", file=sys.stderr)
        return 1

    bad = []
    for sym, has_ret, argc, line in calls:
        if sym not in decls:
            bad.append((line, sym, "no header declaration", "", ""))
            continue
        ret, pc = decls[sym]
        is_void = (ret.replace(" ", "") == "void")
        if argc != pc:
            bad.append((line, sym, "arity", f"call passes {argc}", f"header takes {pc}"))
        elif has_ret and is_void:
            bad.append((line, sym, "returns", "call expects a value", "header returns void"))
        elif not has_ret and not is_void:
            bad.append((line, sym, "returns", "call discards the result", f"header returns {ret}"))

    print(f"check-signatures: {len(calls)} FFI call sites vs {len(decls)} header declarations")
    if bad:
        print("")
        for line, sym, kind, a, b in sorted(bad):
            loc = f"loader.mojo:{line}"
            print(f"  {kind:8s} {sym:46s} {a} / {b}".rstrip() + f"   [{loc}]")
        print(f"\ncheck-signatures: FAILED — {len(bad)} call site(s) disagree with the headers.")
        return 1
    print("\ncheck-signatures: ALL PASSED (arity and void-ness agree at every call site)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
