#!/usr/bin/env python3
"""webgpu.h -> the browser translation layer's tables (#17).

usage: gen_webgpu_js.py [--check]

Reads ffi/include/webgpu/webgpu.h and clang's wasm64 record layouts, plus
web/implemented.txt, and writes:
  web/webgpu_layout.json   every struct: size, field offsets and C types, the
                           SType values, and the function signatures
  web/webgpu_host.mjs      createImports(rt): one wgpu* import per header
                           function. Functions listed in implemented.txt call
                           web/webgpu_impl.mjs; the rest trap and report.
`--check` (CI) fails when either file is stale. Needs clang (pixi exec).
"""
import json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HDR = os.path.join(ROOT, "ffi/include/webgpu/webgpu.h")
LAYOUT = os.path.join(ROOT, "web/webgpu_layout.json")
HOST = os.path.join(ROOT, "web/webgpu_host.mjs")
IMPL = os.path.join(ROOT, "web/implemented.txt")
LLVM = "23.1.4"


def clang_layouts():
    inc = tempfile.mkdtemp()
    open(os.path.join(inc, "math.h"), "w").write("#define INFINITY (1.0f/0.0f)\n#define NAN (0.0f/0.0f)\n")
    cmd = ["clang", "--target=wasm64-unknown-unknown", "-ffreestanding", "-fsyntax-only", "-isystem", inc,
           "-Xclang", "-fdump-record-layouts-complete", HDR]
    if subprocess.run(["which", "clang"], capture_output=True).returncode:
        cmd = ["pixi", "exec", "--spec", "clang=" + LLVM, "--"] + cmd
    r = subprocess.run(cmd, capture_output=True, text=True)
    structs, cur = {}, None
    for line in r.stdout.splitlines():
        m = re.match(r"^\s*(\d+)(?::\d+-\d+)? \| (\s*)(.*)$", line)
        if line.startswith("*** Dumping"):
            cur = None
        elif m:
            depth, text = len(m.group(2)), m.group(3)
            if depth == 0 and text.startswith("struct WGPU"):
                cur = text.split()[1]; structs[cur] = {"size": 0, "fields": []}
            elif depth == 2 and cur:
                t, name = text.rsplit(" ", 1)
                structs[cur]["fields"].append({"n": name, "off": int(m.group(1)), "t": t.replace("struct ", "")})
        elif cur and "sizeof=" in line:
            structs[cur]["size"] = int(re.search(r"sizeof=(\d+)", line).group(1))
    return {k: v for k, v in structs.items() if v["size"]}


def kinds():
    """C type name -> how the JS side reads it: u32 i32 u64 f32 f64 h(andle) p(ointer)."""
    text = open(HDR).read()
    k = {"uint32_t": "u32", "int32_t": "i32", "uint64_t": "u64", "size_t": "u64", "float": "f32", "double": "f64",
         "uint8_t": "u8", "uint16_t": "u16", "int": "i32"}
    for t, n in re.findall(r"typedef (uint32_t|uint64_t) (WGPU\w+);", text):
        k[n] = k[t]
    for n in re.findall(r"typedef WGPUFlags (WGPU\w+);", text):
        k[n] = "u64"
    for n in re.findall(r"\}\s*(WGPU\w+)\s+WGPU_ENUM_ATTRIBUTE;", text):
        k[n] = "u32"
    for n in re.findall(r"typedef struct WGPU\w+Impl\*\s*(WGPU\w+)", text):
        k[n] = "h"
    for n in re.findall(r"typedef \w[\w ]*\(\*(WGPU\w+)\)", text):
        k[n] = "p"
    return k


def kind_of(t, k, structs):
    t = re.sub(r"\bconst\b", "", t).strip()
    if t.endswith("*"):
        return "p"
    if t == "WGPUStringView":
        return "sv"
    if t in structs:
        return "s:" + t
    return k.get(t, "?")


def functions():
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", open(HDR).read(), flags=re.S)
    flat = re.sub(r"\s+", " ", re.sub(r"^#.*$", "", text, flags=re.M))
    fns = {}
    for ret, name, params in re.findall(r"WGPU_EXPORT ([^;(]*?)\b(wgpu[A-Z]\w*)\s*\(([^)]*)\)", flat):
        ps = []
        for p in [x.strip() for x in params.split(",") if x.strip() and x.strip() != "void"]:
            p = re.sub(r"\bWGPU_NULLABLE\b|\bWGPU_NON_NULL\b", "", p).strip()
            t, n = p.rsplit(" ", 1)
            ps.append({"n": n, "t": t.strip()})
        fns[name] = {"ret": re.sub(r"\bWGPU_NULLABLE\b|\bWGPU_NON_NULL\b", "", ret).strip(), "params": ps}
    return fns


def stypes():
    body = re.search(r"typedef enum WGPUSType \{(.*?)\}", open(HDR).read(), re.S).group(1)
    return {k: int(v, 16) for k, v in re.findall(r"WGPUSType_(\w+)\s*=\s*(0x[0-9A-Fa-f]+)", body) if k != "Force32"}


def implemented():
    return [l.strip() for l in open(IMPL) if l.strip() and not l.startswith("#")] if os.path.exists(IMPL) else []


def build():
    fns, impl = functions(), implemented()
    unknown = [n for n in impl if n not in fns]
    if unknown:
        sys.exit("implemented.txt lists functions webgpu.h lacks: " + ", ".join(unknown))
    stypes_ = stypes()
    stypes_["SurfaceSourceCanvasHTMLSelector"] = 0x00050000      # web_structs.mojo
    structs = clang_layouts()
    k = kinds()
    for st in structs.values():
        for f in st["fields"]:
            f["k"] = kind_of(f["t"], k, structs)
    # web_structs.mojo's struct: chain (16 B) + selector WGPUStringView. Not in any header.
    structs["WGPUSurfaceSourceCanvasHTMLSelector"] = {"size": 32, "fields": [
        {"n": "chain", "off": 0, "t": "WGPUChainedStruct", "k": "s:WGPUChainedStruct"},
        {"n": "selector", "off": 16, "t": "WGPUStringView", "k": "sv"}]}
    layout = {"structs": structs, "stypes": stypes_, "functions": fns}
    names = sorted(fns)
    lines = ["// GENERATED by scripts/gen_webgpu_js.py from webgpu.h and web/implemented.txt. Do not edit.",
             "// %d of %d standard webgpu.h functions are implemented; the rest trap with their name." % (len(impl), len(names)),
             "import { impl } from './webgpu_impl.mjs';", "",
             "export const IMPLEMENTED = %s;" % json.dumps(sorted(impl)),
             "export const ALL_FUNCTIONS = %s;" % json.dumps(names), "",
             "export function createImports(rt) {", "  const env = {};"]
    for n in names:
        if n in impl:
            lines.append("  env.%s = (...a) => impl.%s(rt, ...a);" % (n, n))
        else:
            lines.append("  env.%s = () => rt.trap(%s);" % (n, json.dumps(n + " unimplemented on web")))
    lines += ["  return env;", "}", ""]
    return json.dumps(layout, indent=1, sort_keys=True) + "\n", "\n".join(lines), len(impl), len(names)


def main():
    layout, host, n, total = build()
    if "--check" in sys.argv:
        stale = [p for p, t in ((LAYOUT, layout), (HOST, host)) if not os.path.exists(p) or open(p).read() != t]
        if stale:
            print("gen_webgpu_js: stale: " + ", ".join(os.path.relpath(p, ROOT) for p in stale)); return 1
        print("gen_webgpu_js: up to date (%d of %d functions implemented)" % (n, total)); return 0
    open(LAYOUT, "w").write(layout); open(HOST, "w").write(host)
    print("gen_webgpu_js: wrote web/webgpu_layout.json, web/webgpu_host.mjs (%d of %d functions)" % (n, total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
