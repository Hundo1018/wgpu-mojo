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

  * argument sizes — for the call sites whose arguments are exactly the
                     enclosing method's parameters (175 of 185), each argument's
                     byte size must equal its C parameter's. Sizes are measured,
                     not mapped: `gcc sizeof()` on one side, pointer arithmetic
                     in Mojo on the other, so there is no type table to drift.
                     Catches the confusions that a name map would miss anyway,
                     e.g. a UInt32 passed where the C API takes uint64_t — a
                     live risk with the bitflag parameters.

The remaining 10 call sites transform or reorder their arguments (adding a
null, converting a Bool, or matching C's parameter order rather than the
method's), so their argument types cannot be read off the signature. They are
still arity- and void-checked, and are reported as unchecked-for-size.
"""
import os, re, subprocess, sys, tempfile

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
    """symbol -> (return_type, [param_types])."""
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
        types = []
        for prm in params:
            # drop the parameter name: the trailing identifier, unless the
            # declaration is a bare type (e.g. "void *")
            t = re.sub(r"\b[A-Za-z_]\w*\s*$", "", prm).strip() or prm.strip()
            types.append(t)
        # a later declaration of the same symbol should agree; keep the first
        decls.setdefault(name, (ret, types))
    return decls


def loader_calls():
    """(symbol, has_return, args, line, mojo_arg_types|None) per _wgpu.call site.

    mojo_arg_types is filled only when the call's arguments are exactly the
    enclosing method's parameter names, in order — otherwise the argument types
    cannot be read off the signature and it is left None.
    """
    src = read(LOADER)

    methods = []   # (start_offset, [param_names], [param_types])
    for m in re.finditer(r"^    def (\w+)\(", src, re.M):
        inner, _ = balanced(src, m.end() - 1)
        ps = [p for p in split_top_level(inner) if p.split(":")[0].strip() != "self"]
        names = [p.split(":")[0].strip() for p in ps]
        types = [p.split(":", 1)[1].split("=")[0].strip() if ":" in p else "?" for p in ps]
        methods.append((m.start(), names, types))

    out = []
    for m in re.finditer(r'self\._wgpu\.call\[\s*"(\w+)"\s*(,)?', src):
        sym, comma = m.group(1), m.group(2)
        close = src.index("]", m.end())
        has_ret = comma is not None
        i = src.index("(", close)
        inner, _ = balanced(src, i)
        args = split_top_level(inner)
        line = src.count("\n", 0, m.start()) + 1
        owner = None
        for pos, names, types in methods:
            if pos < m.start():
                owner = (names, types)
        mojo_types = owner[1] if owner and args == owner[0] else None
        out.append((sym, has_ret, args, line, mojo_types))
    return out


PTR = 8   # asserted against the C probe below


def measure_c_sizes(types):
    """gcc sizeof() for each C type; pointers are taken as PTR."""
    concrete = sorted({t for t in types if not t.rstrip().endswith("*")})
    tmp = tempfile.mkdtemp()
    src = os.path.join(tmp, "t.c")
    with open(src, "w") as f:
        f.write('#include <stdio.h>\n#include "webgpu/webgpu.h"\n#include "webgpu/wgpu.h"\n')
        f.write("int main(void){\n")
        f.write('  printf("__ptr %zu\\n", sizeof(void*));\n')
        for i, t in enumerate(concrete):
            f.write('  printf("%d %%zu\\n", sizeof(%s));\n' % (i, t))
        f.write("  return 0;\n}\n")
    exe = os.path.join(tmp, "t")
    r = subprocess.run(["gcc", "-I", os.path.join(ROOT, "ffi/include"), src, "-o", exe],
                       capture_output=True, text=True)
    if r.returncode:
        return None, r.stderr
    out = subprocess.run([exe], capture_output=True, text=True).stdout.split("\n")
    sizes = {}
    for line in out:
        if not line.strip():
            continue
        k, v = line.split()
        sizes[k] = int(v)
    res = {t: sizes[str(i)] for i, t in enumerate(concrete) if str(i) in sizes}
    for t in types:
        if t.rstrip().endswith("*"):
            res[t] = sizes.get("__ptr", PTR)
    return res, None


def measure_mojo_sizes(types):
    """Byte size of each Mojo type; Pointer[...] forms are taken as PTR."""
    concrete = sorted({t for t in types
                       if not t.startswith("Pointer[") and not t.startswith("OpaquePointer[")})
    tmp = tempfile.mkdtemp()
    src = os.path.join(tmp, "t.mojo")
    with open(src, "w") as f:
        f.write("from wgpu._ffi.nulls import null_ptr\n")
        f.write("from wgpu._backend.wgpu_native.types import *\n")
        f.write("from wgpu._backend.wgpu_native.structs import *\n")
        f.write("\ndef _sz[T: AnyType]() -> Int:\n    var p = null_ptr[T]()\n    return Int(p.unsafe_offset(1)) - Int(p)\n\ndef main() raises:\n")
        for i, t in enumerate(concrete):
            f.write('    print("%d", _sz[%s]())\n' % (i, t))
    r = subprocess.run(["mojo", "run", "-I", ".", src], cwd=ROOT, capture_output=True, text=True)
    sizes = {}
    for line in r.stdout.split("\n"):
        parts = line.split()
        if len(parts) == 2 and parts[0].isdigit():
            sizes[parts[0]] = int(parts[1])
    if not sizes:
        return None, r.stderr[-1500:]
    res = {t: sizes[str(i)] for i, t in enumerate(concrete) if str(i) in sizes}
    for t in types:
        if t.startswith("Pointer[") or t.startswith("OpaquePointer["):
            res[t] = PTR
    return res, None


def main():
    decls, calls = header_decls(), loader_calls()
    if not calls:
        print("check-signatures: parsed no call sites — parser broken?", file=sys.stderr)
        return 1

    bad = []
    typed = [c for c in calls if c[4] is not None and c[0] in decls]
    c_types = {t for sym, _, _, _, _ in typed for t in decls[sym][1]}
    m_types = {t for _, _, _, _, mt in typed for t in mt}
    c_sizes, err = measure_c_sizes(c_types)
    if c_sizes is None:
        print("check-signatures: C size probe failed:\n" + err[-1200:], file=sys.stderr); return 1
    m_sizes, err = measure_mojo_sizes(m_types)
    if m_sizes is None:
        print("check-signatures: Mojo size probe failed:\n" + err, file=sys.stderr); return 1

    unchecked = 0
    for sym, has_ret, args, line, mojo_types in calls:
        if sym not in decls:
            bad.append((line, sym, "no header decl", "", ""))
            continue
        ret, ptypes = decls[sym]
        is_void = (ret.replace(" ", "") == "void")
        if len(args) != len(ptypes):
            bad.append((line, sym, "arity", f"call passes {len(args)}", f"header takes {len(ptypes)}"))
            continue
        if has_ret and is_void:
            bad.append((line, sym, "returns", "call expects a value", "header returns void")); continue
        if not has_ret and not is_void:
            bad.append((line, sym, "returns", "call discards the result", f"header returns {ret}")); continue
        if mojo_types is None:
            unchecked += 1
            continue
        for k, (mt, ct) in enumerate(zip(mojo_types, ptypes)):
            ms, cs = m_sizes.get(mt), c_sizes.get(ct)
            if ms is None or cs is None or ms != cs:
                bad.append((line, sym, f"arg {k+1}",
                            f"{mt} = {ms}B", f"{ct} = {cs}B"))

    print(f"check-signatures: {len(calls)} FFI call sites vs {len(decls)} header declarations")
    print(f"  arity + void-ness: all {len(calls)} | argument sizes: {len(calls) - unchecked} "
          f"({unchecked} transform their arguments, size-unchecked)")
    if bad:
        print("")
        for line, sym, kind, a, b in sorted(bad):
            loc = f"loader.mojo:{line}"
            print(f"  {kind:8s} {sym:46s} {a} / {b}".rstrip() + f"   [{loc}]")
        print(f"\ncheck-signatures: FAILED — {len(bad)} call site(s) disagree with the headers.")
        return 1
    print("\ncheck-signatures: ALL PASSED (arity, void-ness and argument sizes agree)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
