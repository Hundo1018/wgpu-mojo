#!/usr/bin/env python3
"""WebGPU enum value -> JS string table (#18).

usage: gen_enum_strings.py [--check]

Reads ffi/wgpu-native-meta/webgpu.yml (entry names) and webgpu.h (integer
values) and writes scripts/webgpu_enum_strings.json:
    { "TextureFormat": { "1": "r8unorm", ... }, ... }
`--check` (pixi run check-enum-strings) fails if the file is stale, if any enum
value in types.mojo has no string, or if the table has an entry types.mojo lacks.
Bitflags are passed through as integers and are not in the table.
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scripts/webgpu_enum_strings.json")
SKIP = {"Undefined", "Force32"}   # not strings the browser takes
# Entries whose JS spelling is not the mechanical one. Empty: the rules in
# js_name() cover every entry in v29.0.1.1; add exceptions here with a reason.
EXCEPTIONS = {}


def camel(snake):
    return "".join(t if t.isupper() else t[:1].upper() + t[1:] for t in snake.split("_"))


def js_name(enum, entry):
    low = entry.lower()
    if enum == "texture_format":
        toks = low.split("_")
        if toks[0] in ("bc", ) or re.match(r"^(bc\d|astc)", toks[0]):
            return "-".join(toks)
        if re.match(r"^(etc2|eac)", toks[0]):
            rest = "".join(toks[1:]).replace("srgb", "-srgb")
            return toks[0] + "-" + rest
        s = "".join(toks)
        return s.replace("srgb", "-srgb").replace("stencil8", "-stencil8") if s != "stencil8" else s
    return low.replace("_", "-")


def parse_enums(text):
    """The `enums:` section of webgpu.yml, without a YAML library (the pixi
    environment has none): [{name, entries: [{name} | None]}]."""
    out, inside = [], False
    for line in text.splitlines():
        if re.match(r"^\S", line):
            inside = line.startswith("enums:")
            continue
        if not inside:
            continue
        m = re.match(r"^  - name: \"?([^\s\"]+)\"?\s*$", line)
        if m:
            out.append({"name": m.group(1), "entries": []})
        elif re.match(r"^      - null\s*$", line):
            out[-1]["entries"].append(None)
        else:
            m = re.match(r"^      - name: \"?([^\s\"]+)\"?\s*$", line)
            if m:
                out[-1]["entries"].append({"name": m.group(1)})
    return out


def build():
    meta = {"enums": parse_enums(open(os.path.join(ROOT, "ffi/wgpu-native-meta/webgpu.yml")).read())}
    header = open(os.path.join(ROOT, "ffi/include/webgpu/webgpu.h")).read()
    table, problems = {}, []
    for e in meta["enums"]:
        cname = "WGPU" + camel(e["name"])
        vals = dict(re.findall(r"\b%s_(\w+)\s*=\s*(0x[0-9A-Fa-f]+)" % cname, header))
        norm = {k.lower().replace("_", ""): (k, int(v, 16)) for k, v in vals.items()}
        out = {}
        for ent in e["entries"]:
            if not ent:
                continue
            key = ent["name"].lower().replace("_", "")
            if key in {s.lower() for s in SKIP} or key not in norm:
                if key not in {s.lower() for s in SKIP}:
                    problems.append("%s.%s has no value in webgpu.h" % (cname[4:], ent["name"]))
                continue
            name = EXCEPTIONS.get((e["name"], ent["name"])) or js_name(e["name"], ent["name"])
            out[str(norm[key][1])] = name
        table[cname[4:]] = out
    return table, problems


def mojo_enums():
    src = open(os.path.join(ROOT, "wgpu/_backend/wgpu_native/types.mojo")).read()
    res = {}
    for m in re.finditer(r"^struct WGPU(\w+):\n((?:    [^\n]*\n|\n)*)", src, re.M):
        vals = {}
        for c, v in re.findall(r"^    comptime (\w+): UInt32 = (0x[0-9A-Fa-f]+|\d+)", m.group(2), re.M):
            vals[c] = int(v, 0)
        if vals:
            res[m.group(1)] = vals
    return res


def main():
    table, problems = build()
    text = json.dumps(table, indent=1, sort_keys=True) + "\n"
    if "--check" not in sys.argv:
        open(OUT, "w").write(text)
        print("gen_enum_strings: %d enums, %d values -> %s" % (len(table), sum(map(len, table.values())), OUT))
        return 1 if problems else 0
    bad = list(problems)
    if not os.path.exists(OUT) or open(OUT).read() != text:
        bad.append("scripts/webgpu_enum_strings.json is stale; run gen_enum_strings.py")
    n = 0
    for enum, vals in mojo_enums().items():
        if enum not in table:
            continue     # bitflags and non-enums
        have = {int(k) for k in table[enum]}
        for c, v in vals.items():
            if c in SKIP or v == 0x7FFFFFFF:
                continue
            n += 1
            if v not in have:
                bad.append("types.mojo %s.%s = %d has no JS string" % (enum, c, v))
        for v in sorted(have - set(vals.values())):
            bad.append("table %s has value %d that types.mojo lacks" % (enum, v))
    print("check-enum-strings: %d enum values in types.mojo checked against %d tables" % (n, len(table)))
    if bad:
        print("\n".join("  " + b for b in bad)); print("check-enum-strings: FAILED"); return 1
    print("check-enum-strings: ALL PASSED"); return 0


if __name__ == "__main__":
    sys.exit(main())
