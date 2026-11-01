"""Retarget Modular host IR to wasm for a recent llc (LLVM >= 23). From ludens-engine tools/wasm/poc.
usage: python3 -I retarget.py in.ll out.ll [wasm64|wasm32]
Only: triple/datalayout swap, strip x86 target-cpu/features, stub x86 MXCSR intrinsics.
"""
import re, sys

src, dst = sys.argv[1], sys.argv[2]
arch = sys.argv[3] if len(sys.argv) > 3 else "wasm64"
DL = {"wasm64": "e-m:e-p:64:64-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20",
      "wasm32": "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20"}[arch]
TRIPLE = {"wasm64": "wasm64-unknown-unknown", "wasm32": "wasm32-unknown-unknown"}[arch]
n_mx = 0
with open(src) as fi, open(dst, "w") as fo:
    for line in fi:
        if line.startswith("target datalayout"):
            line = f'target datalayout = "{DL}"\n'
        elif line.startswith("target triple"):
            line = f'target triple = "{TRIPLE}"\n'
        elif line.startswith("attributes #"):
            line = re.sub(r'"target-(cpu|features)"="[^"]*"', "", line)
            line = re.sub(r"\{\s*\}", '{ "wasm-retargeted" }', line)
        m = re.match(r"\s*call void @llvm\.x86\.sse\.stmxcsr\(ptr (%\S+)\)", line)
        if m:
            line = f"  store i32 8064, ptr {m.group(1)}, align 4\n"; n_mx += 1
        if "@llvm.x86.sse.ldmxcsr" in line or line.startswith("declare void @llvm.x86.sse.stmxcsr"):
            n_mx += 1
            continue
        fo.write(line)
print(f"retarget: {arch}, x86 mxcsr sites stubbed: {n_mx}", file=sys.stderr)
