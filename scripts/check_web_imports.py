#!/usr/bin/env python3
"""Web-target ABI gates (#14). Needs emdawnwebgpu's header (build-web fetches it).

usage: check_web_imports.py DAWN_INCLUDE [IR.ll ...]

1. Every wgpu* function the web IR calls is declared in emdawnwebgpu's
   webgpu.h. Anything else would link against nothing in the browser.
2. target.mojo's _NATIVE_ONLY is exactly: every function in wgpu-native's
   wgpu.h, plus every function loader.mojo binds that emdawnwebgpu's webgpu.h
   lacks. That list is what turns a native-only call into a compile error.
3. No loader method passes a WGPUStringView parameter to a C call except
   through sv_arg(): by value, Mojo's host-lowered IR splits it into two i64s
   where emscripten's wasm64 ABI expects a pointer.
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
    dawn = os.path.join(sys.argv[1], "webgpu/webgpu.h")
    lls = sys.argv[2:]
    bad = []
    dawn_fns = functions(dawn)
    if len(dawn_fns) < 150:
        print("check-web-imports: parsed only %d functions from %s" % (len(dawn_fns), dawn))
        return 1

    for ll in lls:
        called = set(re.findall(r"^declare [^@]*@(wgpu[A-Z]\w*)\(", read(ll), re.M))
        missing = sorted(called - dawn_fns)
        bad += ["%s calls %s, which emdawnwebgpu's webgpu.h does not declare" % (os.path.basename(ll), f)
                for f in missing]
        print("  %s: %d wgpu imports, all in webgpu.h: %s" % (os.path.basename(ll), len(called), not missing))

    loader = read(os.path.join(ROOT, "wgpu/_backend/wgpu_native/loader.mojo"))
    bound = set(re.findall(r'_wgpu\.call\["(wgpu[A-Z]\w*)"', loader))
    want = functions(os.path.join(ROOT, "ffi/include/webgpu/wgpu.h")) | (bound - dawn_fns)
    target = read(os.path.join(ROOT, "wgpu/_backend/wgpu_native/target.mojo"))
    block = re.search(r"_NATIVE_ONLY = \((.*?)\n\)", target, re.S).group(1)
    have = set(re.findall(r'"(wgpu\w+)"', block))
    for f in sorted(want - have):
        bad.append("_NATIVE_ONLY lacks %s" % f)
    for f in sorted(have - want):
        bad.append("_NATIVE_ONLY lists %s, which the web target has" % f)
    print("  _NATIVE_ONLY: %d functions, matches wgpu.h + loader-bound \\ webgpu.h: %s"
          % (len(have), want == have))

    n_sv = 0
    for m in re.finditer(r"\n    def (\w+)\(\s*self,(.*?)\)[^:]*:\n(.*?)(?=\n    def |\n# |\Z)", loader, re.S):
        params = re.findall(r"(\w+)\s*:\s*WGPUStringView\b", m.group(2))
        for p in params:
            n_sv += 1
            for call in re.findall(r"_wgpu\.call\[[^\]]*\]\(([^)]*(?:\([^)]*\))?[^)]*)\)", m.group(3)):
                args = [a.strip() for a in call.split(",")]
                if p in args:
                    bad.append("%s passes WGPUStringView `%s` by value; use sv_arg(%s)" % (m.group(1), p, p))
    print("  WGPUStringView parameters routed through sv_arg: %d" % n_sv)

    if bad:
        print("\ncheck-web-imports: FAILED")
        for b in bad:
            print("  " + b)
        return 1
    print("\ncheck-web-imports: ALL PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
