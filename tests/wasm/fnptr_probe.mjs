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

// 2. A real wgpu callback, which takes a WGPUStringView message (16 B).
// Mojo lowers abi("C") for the host (x86-64 SysV) before the IR is retargeted,
// so a by-value struct arrives as two i64s; clang's wasm C ABI passes it by
// pointer. `-D WGPU_TARGET=web` (#14) declares the parameter as a pointer, which
// is what makes the browser's call_indirect match.
//   host build: 5 wasm params, the C call traps (why the web flag exists)
//   web build:  4 wasm params, the C call runs and stores the status
const web = process.argv[3] === "web";
const cb = x.fnptr_buffer_map_callback();
check(cb > 0n && cb < BigInt(table.length), `buffer_map_callback() = ${cb}: a table index`);
const want = web ? 4 : 5;
check(table.get(cb).length === want,
      `buffer_map_callback() entry has ${want} wasm params (${web ? "web: message by pointer, as clang" : "host SysV split"}), got ${table.get(cb).length}`);
if (web) {
  let err = null;
  try { x.call_map_cb(cb, x.slot_addr()); } catch (e) { err = e; }
  check(err === null && x.slot_status() === 1,
        `C call through WGPUBufferMapCallback runs and writes status 1 (got ${err ?? x.slot_status()})`);
} else {
  let trapped = false;
  try { x.call_map_cb(cb, 0n); } catch (e) { trapped = /signature mismatch/.test(String(e.message ?? e)); }
  check(trapped, "C call through WGPUBufferMapCallback traps with a signature mismatch (host-lowered build)");
}
process.exitCode = failed ? 1 : 0;
