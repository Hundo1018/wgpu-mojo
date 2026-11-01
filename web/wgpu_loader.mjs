// Instantiate a wgpu-mojo wasm64 module (#17) with the shared ludens-wasm-rt runtime (host.mjs).
// Imports come from the generated webgpu_host.mjs.
import { createImports } from './webgpu_host.mjs';
import { instantiate } from './host.mjs';
import { Runtime } from './webgpu_runtime.mjs';

export async function loadWasm(url, { layoutUrl = './webgpu_layout.json', enumsUrl = './webgpu_enum_strings.json' } = {}) {
  const here = new URL(import.meta.url);
  const json = async (u) => (await fetch(new URL(u, here))).json();
  const [layout, enums, bytes] = await Promise.all([json(layoutUrl), json(enumsUrl), fetch(url).then((r) => r.arrayBuffer())]);
  const rt = new Runtime(layout, enums);
  // host.mjs composes the imports and enforces the re-entry rule (ludens-wasm-rt #4).
  const host = await instantiate(bytes, { libs: [() => ({ env: createImports(rt) })] });
  rt.attach(host);
  return { rt, host, ...host.exports };
}
