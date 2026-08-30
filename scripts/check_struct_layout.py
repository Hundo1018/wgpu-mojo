#!/usr/bin/env python3
"""Verify every FFI struct's layout against the real C headers.

Struct layout is the one part of the binding that no other gate can see: a
struct can have the right name, resolve fine, and still silently corrupt every
read if a field is missing, extra, or mistyped. Two such bugs were found by
accident in 2026-08 — WGPUSupportedInstanceFeatures carried a nextInChain the
header does not have, and WGPUInstanceLimits was missing timedWaitAnyMaxCount.
Both were latent because nothing used them yet.

Checks, for every struct declared in structs.mojo that also exists in the
headers:
  * byte size, against `gcc sizeof()` on the real headers
  * field count, against the header's field list

Size alone would miss two same-size fields merged into one; field count alone
would miss a wrong field type. Together they catch both.

What this still does not check is field *order* with identical sizes. Doing that
needs per-field offsets on the Mojo side, which needs a constructed instance of
each struct, which needs valid arguments for all ~88 of them.
"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRUCTS = os.path.join(ROOT, "wgpu/_backend/wgpu_native/structs.mojo")
HEADERS = [os.path.join(ROOT, "ffi/include/webgpu/webgpu.h"),
           os.path.join(ROOT, "ffi/include/webgpu/wgpu.h")]


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def main():
    mojo = read(STRUCTS)
    hdr = "".join(read(h) for h in HEADERS)

    c_structs = set(re.findall(r"^\}\s*(WGPU\w+)\s*(?:WGPU_STRUCTURE_ATTRIBUTE)?\s*;", hdr, re.M))
    c_structs |= set(re.findall(r"^typedef struct (WGPU\w+)", hdr, re.M))
    names = [n for n in sorted(set(re.findall(r"^struct (WGPU\w+)", mojo, re.M))) if n in c_structs]
    if not names:
        print("check-struct-layout: no structs found — parser broken?", file=sys.stderr)
        return 1

    def mojo_fields(n):
        m = re.search(r"^struct %s\b[^\n]*:\n((?:(?:    [^\n]*)?\n)*?)(?=\S|\Z)" % n, mojo, re.M)
        return re.findall(r"^    var (\w+)\s*:", m.group(1), re.M) if m else None

    def c_fields(n):
        m = re.search(r"typedef struct %s\s*\n?\{(.*?)\n\}\s*%s" % (n, n), hdr, re.S) \
            or re.search(r"typedef struct\s*\{(.*?)\n\}\s*%s" % n, hdr, re.S)
        if not m:
            return None
        body = re.sub(r"/\*.*?\*/", "", m.group(1), flags=re.S)
        body = re.sub(r"//[^\n]*", "", body)
        return re.findall(r"^\s*[A-Za-z_][\w \*]*?[\* ](\w+)\s*;", body, re.M)

    tmp = tempfile.mkdtemp()

    # --- C side: sizeof for each struct ---
    csrc = os.path.join(tmp, "sz.c")
    with open(csrc, "w") as f:
        f.write('#include <stdio.h>\n#include "webgpu/webgpu.h"\n#include "webgpu/wgpu.h"\nint main(void){\n')
        for n in names:
            f.write('  printf("%s %%zu\\n", sizeof(%s));\n' % (n, n))
        f.write("  return 0;\n}\n")
    exe = os.path.join(tmp, "sz")
    r = subprocess.run(["gcc", "-I", os.path.join(ROOT, "ffi/include"), csrc, "-o", exe],
                       capture_output=True, text=True)
    if r.returncode:
        print("check-struct-layout: C probe failed to build:\n" + r.stderr, file=sys.stderr)
        return 1
    c_sizes = dict(l.split() for l in subprocess.run([exe], capture_output=True, text=True).stdout.split("\n") if l)

    # --- Mojo side: same sizes via pointer arithmetic ---
    msrc = os.path.join(tmp, "sz.mojo")
    with open(msrc, "w") as f:
        f.write("from wgpu._ffi.nulls import null_ptr\nfrom wgpu._backend.wgpu_native.structs import (\n")
        for n in names:
            f.write("    %s,\n" % n)
        f.write(")\n\ndef _sz[T: AnyType]() -> Int:\n    var p = null_ptr[T]()\n    return Int(p + 1) - Int(p)\n\ndef main() raises:\n")
        for n in names:
            f.write('    print("%s", _sz[%s]())\n' % (n, n))
    r = subprocess.run(["mojo", "run", "-I", ".", msrc], cwd=ROOT, capture_output=True, text=True)
    m_sizes = dict(l.split() for l in r.stdout.split("\n") if l.startswith("WGPU") and len(l.split()) == 2)
    if not m_sizes:
        print("check-struct-layout: Mojo probe produced nothing:\n" + r.stderr[-2000:], file=sys.stderr)
        return 1

    bad = []
    for n in names:
        cs, ms = c_sizes.get(n), m_sizes.get(n)
        if cs is None or ms is None:
            bad.append((n, "missing", ms, cs))
        elif cs != ms:
            bad.append((n, "size", ms, cs))
        else:
            mf, cf = mojo_fields(n), c_fields(n)
            if mf is None or cf is None:
                bad.append((n, "unparsed", mf and len(mf), cf and len(cf)))
            elif len(mf) != len(cf):
                bad.append((n, "fields", len(mf), len(cf)))

    print("check-struct-layout: %d structs checked against %s" %
          (len(names), " + ".join(os.path.basename(h) for h in HEADERS)))
    if bad:
        print("")
        for n, kind, mv, cv in bad:
            print("  %-9s %-44s mojo=%s  header=%s" % (kind, n, mv, cv))
        print("\ncheck-struct-layout: FAILED — %d struct(s) disagree with the headers." % len(bad))
        print("  A layout mismatch silently corrupts every read through that struct.")
        return 1
    print("\ncheck-struct-layout: ALL PASSED (size and field count agree for all %d)" % len(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
