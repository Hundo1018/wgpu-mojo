#!/usr/bin/env python3
"""Web-target ABI gates (#14, #15).

usage: check_web_imports.py [IR.ll ...]

1. Every wgpu* function the web IR calls is a standard webgpu.h function the
   browser's WebGPU can express. Anything else would have no JS to land on.
2. target.mojo's _NATIVE_ONLY is exactly: every function in wgpu-native's
   wgpu.h, plus every function loader.mojo binds that is not a WebGPU API call
   (wgpu-native's webgpu.h carries the `*SetImmediates` calls, which the
   browser does not have). That list is what turns a native-only call into a
   compile error.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


def functions(header):
    """Functions a header declares. webgpu.h marks them WGPU_EXPORT; wgpu-native's
    wgpu.h does not, so any `wgpuX(` outside comments and macros counts there."""
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", read(header), flags=re.S)
    text = re.sub(r"^#.*$", "", text, flags=re.M)
    flat = re.sub(r"\s+", " ", text)
    if "WGPU_EXPORT" in flat:
        return set(re.findall(r"WGPU_EXPORT [^;(]*?\b(wgpu[A-Z]\w*)\s*\(", flat))
    return set(re.findall(r"\b(wgpu[A-Z]\w*)\s*\(", flat))


def main():
    hdr = os.path.join(ROOT, "ffi/include/webgpu/webgpu.h")
    lls = sys.argv[1:]
    bad = []
    all_fns = functions(hdr)
    if len(all_fns) < 150:
        print("check-web-imports: parsed only %d functions from %s" % (len(all_fns), hdr))
        return 1
    web_fns = {f for f in all_fns if "SetImmediates" not in f}

    for ll in lls:
        called = set(re.findall(r"^declare [^@]*@(wgpu[A-Z]\w*)\(", read(ll), re.M))
        missing = sorted(called - web_fns)
        bad += ["%s calls %s, which the browser's WebGPU has no counterpart for" % (os.path.basename(ll), f)
                for f in missing]
        print("  %s: %d wgpu imports, all standard webgpu.h: %s" % (os.path.basename(ll), len(called), not missing))

    loader = read(os.path.join(ROOT, "wgpu/_backend/wgpu_native/loader.mojo"))
    bound = set(re.findall(r'_wgpu\.call\["(wgpu[A-Z]\w*)"', loader))
    want = functions(os.path.join(ROOT, "ffi/include/webgpu/wgpu.h")) | (bound - web_fns)
    target = read(os.path.join(ROOT, "wgpu/_backend/wgpu_native/target.mojo"))
    block = re.search(r"_NATIVE_ONLY = \((.*?)\n\)", target, re.S).group(1)
    have = set(re.findall(r'"(wgpu\w+)"', block))
    for f in sorted(want - have):
        bad.append("_NATIVE_ONLY lacks %s" % f)
    for f in sorted(have - want):
        bad.append("_NATIVE_ONLY lists %s, which the web target has" % f)
    print("  _NATIVE_ONLY: %d functions, matches wgpu.h + loader-bound \\ web: %s"
          % (len(have), want == have))

    if bad:
        print("\ncheck-web-imports: FAILED")
        for b in bad:
            print("  " + b)
        return 1
    print("\ncheck-web-imports: ALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
