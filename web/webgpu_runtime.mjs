// Hand-written half of the browser translation layer (#17): wasm memory access,
// the handle table, the layout-driven struct reader, and the deferred-callback
// queue (#19). Knows webgpu.h only through web/webgpu_layout.json.
//
// Re-entry rule: JS never calls into wasm from a Promise/microtask. Async
// results are queued with defer(); wgpuInstanceProcessEvents (a Mojo call) runs
// drain(), which is the only place callbacks are invoked.

export const STRLEN = 0xFFFFFFFFFFFFFFFFn;
export const WHOLE_SIZE = 0xFFFFFFFFFFFFFFFFn;
const U32_UNDEF = 0xFFFFFFFF;

export class Runtime {
  constructor(layout, enums) {
    this.layout = layout;
    this.enums = enums;
    this.handles = new Map();
    this.nextHandle = 1n;
    this.queue = [];
    this.depth = 0;          // >0 while a Mojo export (or import) is running
    this.errors = [];
    this.unimplemented = new Set();
    this.mapped = new Map(); // buffer handle -> {ptr, ab, offset, size, write}
    this.futures = 1n;
    this.cbLog = [];          // futures in the order their callbacks ran
  }

  attach(exports) {
    this.exports = exports;
    this.memory = exports.memory;
    this.table = exports.__indirect_function_table;
  }

  // ---- wasm memory ----
  get view() {
    if (this._buf !== this.memory.buffer) {
      this._buf = this.memory.buffer;
      this._dv = new DataView(this._buf);
      this._u8 = new Uint8Array(this._buf);
    }
    return this._dv;
  }
  get u8() { this.view; return this._u8; }
  bytes(ptr, n) { return this.u8.subarray(Number(ptr), Number(ptr) + Number(n)); }
  alloc(n) { return this.exports.mw_alloc(BigInt(n)); }
  free(p) { this.exports.mw_free(p); }

  // A JS string in wasm memory: [ptr, len]. Caller frees ptr.
  str_in(s) {
    const b = new TextEncoder().encode(s);
    const p = this.alloc(b.length + 1);
    this.u8.set(b, Number(p));
    this.u8[Number(p) + b.length] = 0;
    return [p, b.length];
  }
  str_out(ptr, len) {
    if (!ptr) return '';
    let n = len === STRLEN ? undefined : Number(len);
    const start = Number(ptr);
    if (n === undefined) { n = 0; while (this.u8[start + n]) n++; }
    return new TextDecoder().decode(this.u8.subarray(start, start + n));
  }

  // ---- handles ----
  put(obj) { const id = this.nextHandle++; this.handles.set(id, obj); return id; }
  get(id) {
    const o = this.handles.get(BigInt(id));
    if (o === undefined) throw new Error('wgpu: unknown handle ' + id);
    return o;
  }
  drop(id) { this.handles.delete(BigInt(id)); }

  // ---- structs ----
  read(name, ptr) {
    const def = this.layout.structs[name];
    if (!def) throw new Error('wgpu: no layout for ' + name);
    const base = Number(ptr), dv = this.view, rt = this, o = {};
    for (const f of def.fields) {
      const at = base + f.off;
      Object.defineProperty(o, f.n, { enumerable: true, get() {
        const d = rt.view;
        switch (f.k) {
          case 'u32': return d.getUint32(at, true);
          case 'i32': return d.getInt32(at, true);
          case 'u64': case 'h': case 'p': return d.getBigUint64(at, true);
          case 'f32': return d.getFloat32(at, true);
          case 'f64': return d.getFloat64(at, true);
          case 'u16': return d.getUint16(at, true);
          case 'u8': return d.getUint8(at);
          case 'sv': return rt.str_out(d.getBigUint64(at, true), d.getBigUint64(at + 8, true));
          default:
            if (f.k.startsWith('s:')) return rt.read(f.k.slice(2), at);
            throw new Error('wgpu: field kind ' + f.k);
        }
      } });
    }
    o.__ptr = base;
    return o;
  }
  // `count` structs of `name` laid out back to back at `ptr`.
  array(name, ptr, count) {
    const size = this.layout.structs[name].size, out = [];
    for (let i = 0; i < Number(count); i++) out.push(this.read(name, Number(ptr) + i * size));
    return out;
  }
  u64s(ptr, count) {
    const out = [];
    for (let i = 0; i < Number(count); i++) out.push(this.view.getBigUint64(Number(ptr) + i * 8, true));
    return out;
  }
  // First struct in a nextInChain with this SType name, or null.
  chain(first, stypeName) {
    const want = this.layout.stypes[stypeName];
    for (let p = Number(first); p;) {
      const next = this.view.getBigUint64(p, true), st = this.view.getUint32(p + 8, true);
      if (st === want) return p;
      p = Number(next);
    }
    return null;
  }

  // ---- enums ----
  enumStr(type, v) {
    const s = this.enums[type]?.[String(v)];
    if (s === undefined) throw new Error(`wgpu: ${type} value ${v} has no JS string`);
    return s;
  }
  enumInt(type, str) {
    for (const [k, v] of Object.entries(this.enums[type] ?? {})) if (v === str) return Number(k);
    throw new Error(`wgpu: ${type} has no value for "${str}"`);
  }
  optEnum(type, v) { return v === 0 ? undefined : this.enumStr(type, v); }  // 0 = Undefined
  u32(v) { return v === U32_UNDEF ? undefined : v; }

  // ---- async results ----
  defer(fn) { this.queue.push(fn); }
  drain() {
    // Callbacks may queue more work; those run on the next drain.
    const batch = this.queue.splice(0);
    for (const fn of batch) fn();
  }
  // Call a C callback (a function-table index from c_fn_ptr). i64 params are BigInt.
  call_fn(cb, ...args) {
    if (this.depth === 0) throw new Error('wgpu: re-entry into wasm from a microtask (call_fn outside a wasm call)');
    const f = this.table.get(BigInt(cb));
    try { return f(...args); } catch (e) { throw new Error(`call_fn(${cb}) with ${f.length} params, args ${args.map((a) => typeof a + ':' + a)}: ${e.message}`); }
  }

  newFuture() { return this.futures++; }
  trap(msg) {
    this.unimplemented.add(msg);
    const m = 'wgpu: ' + msg;
    console.error(m);
    if (typeof document !== 'undefined') document.title = 'FAIL ' + msg;
    throw new Error(m);
  }
}
