// Drives fnptr_probe.wasm (scripts/check-wasm-fnptr.sh). Node >= 24 (table64).
import { readFileSync } from "node:fs";

const bytes = readFileSync(process.argv[2]);
const mod = new WebAssembly.Module(bytes);
const imports = {};
for (const imp of WebAssembly.Module.imports(mod)) {
  imports[imp.module] ??= {};
  imports[imp.module][imp.name] = () => { throw new Error(`unexpected import ${imp.module}.${imp.name}`); };
}
const { exports: x } = new WebAssembly.Instance(mod, imports);
const table = x.__indirect_function_table;
let failed = 0;
const check = (ok, msg) => { console.log(`${ok ? "PASS" : "FAIL"} ${msg}`); if (!ok) failed++; };

// 1. c_fn_ptr is a small table index, and the entry behind it is the Mojo fn.
const idx = x.fnptr_add1();
check(typeof idx === "bigint" && idx > 0n && idx < BigInt(table.length),
      `c_fn_ptr(add1) = ${idx}: a function-table index (table length ${table.length})`);
check(table.get(idx)(41) === 42, "table.get(c_fn_ptr(add1))(41) === 42 (host-side call, emscripten getWasmTableEntry)");
check(x.call_int_cb(idx, 41) === 42, "C call_indirect through c_fn_ptr(add1) returns 42");

// 2. A real wgpu callback, which takes WGPUStringView (16 B) by value.
// PINNED LIMITATION: Mojo lowers abi("C") for the host (x86-64 SysV) before the
// IR is retargeted, so the struct arrives as two i64s (5 wasm params). clang's
// wasm C ABI passes it indirectly (4 params), so the browser side's
// call_indirect fails its signature check. If either assertion below starts
// failing, the ABI changed (e.g. Mojo gained a real wasm target): revisit
// c_fn_ptr's docstring and #14.
const cb = x.fnptr_buffer_map_callback();
check(cb > 0n && cb < BigInt(table.length), `buffer_map_callback() = ${cb}: a table index`);
check(table.get(cb).length === 5,
      `buffer_map_callback() entry has 5 wasm params (host SysV split; clang wasm ABI expects 4), got ${table.get(cb).length}`);
let trapped = false;
try { x.call_map_cb(cb, 0n); } catch (e) { trapped = /signature mismatch/.test(String(e.message ?? e)); }
check(trapped, "C call through WGPUBufferMapCallback traps with a signature mismatch (pinned limitation)");
process.exitCode = failed ? 1 : 0;
