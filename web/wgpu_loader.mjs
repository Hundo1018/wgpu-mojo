// Instantiate a wgpu-mojo wasm64 module (#17). Imports come from the generated
// webgpu_host.mjs; exports are wrapped so the runtime knows when it is inside
// a wasm call (the re-entry rule in webgpu_runtime.mjs).
import { createImports } from './webgpu_host.mjs';
import { Runtime } from './webgpu_runtime.mjs';

export async function loadWasm(url, { layoutUrl = './webgpu_layout.json', enumsUrl = './webgpu_enum_strings.json' } = {}) {
  const here = new URL(import.meta.url);
  const json = async (u) => (await fetch(new URL(u, here))).json();
  const [layout, enums, bytes] = await Promise.all([json(layoutUrl), json(enumsUrl), fetch(url).then((r) => r.arrayBuffer())]);
  const rt = new Runtime(layout, enums);
  // Imports run inside a wasm call; count them so call_fn is legal there.
  const env = {};
  for (const [name, fn] of Object.entries(createImports(rt))) {
    env[name] = (...a) => { rt.depth++; try { return fn(...a); } finally { rt.depth--; } };
  }
  const { instance } = await WebAssembly.instantiate(bytes, { env });
  rt.attach(instance.exports);
  const M = { rt };
  for (const [name, f] of Object.entries(instance.exports)) {
    M[name] = typeof f === 'function' && !name.startsWith('mw_')
      ? (...a) => { rt.depth++; try { return f(...a); } finally { rt.depth--; } }
      : f;
  }
  return M;
}
