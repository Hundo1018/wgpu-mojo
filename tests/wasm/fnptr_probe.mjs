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
check(table.get(idx)(41) === 42, "table.get(c_fn_ptr(add1))(41) === 42 (host-side call)");
check(x.call_int_cb(idx, 41) === 42, "C call_indirect through c_fn_ptr(add1) returns 42");

// 2. A real wgpu callback, which takes a WGPUStringView message (16 B). Mojo
// lowers abi("C") for the host (x86-64 SysV), so the struct arrives as two i64s
// (pointer, length). The JS translation layer calls the table entry that way:
// call_fn(cb, status, msgPtr, msgLen, userdata1, userdata2).
const cb = x.fnptr_buffer_map_callback();
check(cb > 0n && cb < BigInt(table.length), `buffer_map_callback() = ${cb}: a table index`);
check(table.get(cb).length === 5,
      `buffer_map_callback() entry has 5 wasm params (status, msg ptr, msg len, ud1, ud2), got ${table.get(cb).length}`);
let err = null;
try { table.get(cb)(1, 0n, 0n, x.slot_addr(), 0n); } catch (e) { err = e; }
check(err === null && x.slot_status() === 1,
      `host-side call through WGPUBufferMapCallback runs and writes status 1 (got ${err ?? x.slot_status()})`);
process.exitCode = failed ? 1 : 0;
