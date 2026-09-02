# Binding Roadmap

Coverage of wgpu-native **v29.0.0.0**, what is deliberately left out, and what
remains.

Reproduce every number here with:

```bash
pixi run check-symbols
```

Last measured: 2026-08-30, against `ffi/lib/libwgpu_native.so`.

## Where we are

| Category | Bound | Target | Coverage |
|---|---:|---:|---:|
| **C functions, vs. the target surface** | **185** | **185** | **100%** |
| C functions, vs. everything exported | 185 | 226 | 81.9% |
| Structs, vs. the target surface | 101 | 101 | **100%** |
| Structs, vs. every struct in the headers | 101 | 113 | 89.4% |
| Struct layouts verified against `gcc sizeof()` | 88 | 88 | **100%** |
| FFI call sites with arity + void-ness checked | 185 | 185 | **100%** |
| ↳ also checked for argument sizes | 175 | 185 | 94.6% |
| C bridge result-struct pairs verified | 5 | 5 | **100%** |
| Enum groups | 59 + 5 bitflags | 56 header enums | substantially complete |
| Handle newtypes | 22 | all WebGPU objects | 100% |

**226 is the wrong denominator.** The library exports 226 `wgpu*` symbols, but
40 of them are `unimplemented!()` stubs that abort the process when called, and
1 more is excluded for cause. The target surface — what upstream actually
implements, minus what we deliberately skip — is 185, and all 185 are bound.
Everything this binding names both resolves *and* works.

## How coverage is measured

`scripts/check-symbols.sh` runs three checks, none of them hand-maintained:

1. **Resolution.** Every `"wgpu*"` string literal in `wgpu/` and `wgpu_max/`,
   plus every `wgpuXxx(` call in `ffi/*.c`, must be exported by the library.
   Catches renamed symbols — wgpu-native v29 renamed the push-constant entry
   points to `*SetImmediates`, and the stale bindings compiled fine because FFI
   symbols resolve lazily at the call site.

2. **Stubs.** wgpu-native exports `unimplemented!()` stubs that link cleanly and
   panic in Rust across the C ABI when called, aborting uncatchably. Detected
   two ways, unioned: named messages via `strings`, and structurally — a
   function that panics unconditionally never returns, so its body contains
   `ud2` and no `ret`. Real functions carry `ud2` on cold paths but always have
   a `ret`, which separates the two exactly. `scripts/known-unimplemented.txt`
   is the ratchet and is currently empty.

3. **Classification.** Anything implemented upstream but neither bound nor
   listed in `scripts/excluded-symbols.txt` fails the gate. An upstream bump
   therefore cannot silently widen the gap.

`scripts/check_struct_layout.py` (`pixi run check-struct-layout`) covers the
struct side. For all 88 FFI structs present in both the Mojo layer and the
headers it compares byte size against `gcc sizeof()`, field count against the
header's field list, and **field order** by matching each field's name
positionally (normalised, so `next_in_chain` matches `nextInChain` and `stype`
matches `sType`, with no alias table). The three are complementary: size alone
misses two same-size fields merged into one, count alone misses a wrong field
type, and neither sees a reordering — comparing offsets would not either, since
swapping two same-sized fields leaves every offset unchanged. All three failure
modes are verified by mutation.

It also checks the **C callback bridge contract**: the five `_*Result` structs in
`loader.mojo` against the `Mojo*Result` typedefs the callbacks in
`ffi/wgpu_callbacks.c` write through, measured by compiling the bridge itself.
`CLAUDE.md` flags breaking this as silently corrupting the result, and nothing
verified it before.

`scripts/check_signatures.py` (`pixi run check-signatures`) covers the call side.
All 185 `self._wgpu.call` sites are checked against their header declaration for
argument count and void-ness, and 175 of them additionally for **argument
sizes** — each argument's byte width against its C parameter's. Sizes are
measured on both sides (`gcc sizeof()`, and pointer arithmetic in Mojo) rather
than mapped through a type table, so there is nothing to drift. That catches the
confusion a name map would miss anyway: a `UInt32` passed where the C API takes
`uint64_t`, a live risk with the bitflag parameters. All three checks are
verified by mutation.

The other 10 call sites transform or reorder their arguments — adding a null,
converting a `Bool`, or matching C's parameter order rather than the method's —
so their argument types cannot be read off the enclosing signature. They are
still arity- and void-checked, and the count is reported.

It found two dropped return values: `wgpuSurfacePresent`'s `WGPUStatus` and the
blocking `wgpuDevicePoll` inside `buffer_map_async`.

What is still *not* measured:

- **Argument types beyond their width.** Two distinct 8-byte types are
  interchangeable as far as this gate is concerned — a `WGPUBufferHandle` passed
  where a `WGPUTextureHandle` belongs would pass. The handle newtypes make that
  hard to do accidentally in Mojo, which is why width was the check worth having.
- **The 10 argument-transforming call sites**, listed above.

## Deliberate exclusions

One symbol, with the reason recorded in `scripts/excluded-symbols.txt`:

| Symbol | Why |
|---|---|
| `wgpuDeviceCreateShaderModuleSpirV` | Reports an error on Vulkan/NVIDIA even with the `SpirvShaderPassthrough` feature requested. SPIR-V works through the standard `WGPUShaderSourceSPIRV` chain, which is bound and tested in `tests/test_spirv.mojo`. |

Twelve structs are excluded for cause as well (same file): the `ExternalTexture`
binding structs (that object's whole API is stubs), `WGPUTextureBindingViewDimension`
(its only consumer is a stub), WebXR, the Windows / Android / UWP surface
sources, the four display handles, and `WGPUSurfaceSourceMetalLayer` — which
belongs to Tier 1 below.

## Tier 0 — RESOLVED: abort-on-call symbols removed

29 bound symbols were `unimplemented!()` stubs reachable through the public API:
every `set_label()`, `Buffer.map_state()`, both `create_*_pipeline_async()`, and
`ShaderModule.get_compilation_info()`. All were removed at every layer, along
with the three C bridge paths behind them. A 30th,
`wgpuTextureGetTextureBindingViewDimension`, was caught later by the improved
detector and removed the same way.

Two earlier sessions had each found one instance of this and worked around it
locally without generalising. The gate now generalises it.

## Tier 1 — macOS cannot open a window (OUTSTANDING)

**The only unfinished item, and it needs hardware this project does not have.**

`pixi.toml` declares `platforms = ["linux-64", "osx-arm64"]` and CI builds on
macOS arm64, but surface creation only supports Xlib and Wayland. On macOS the
library loads and headless compute works; anything windowed has no path at all.
Only the SType enum value exists — there is no `WGPUSurfaceSourceMetalLayer`
descriptor and no plumbing.

The three Metal native-handle getters (`wgpuDeviceGetNativeMetalDevice`,
`wgpuQueueGetNativeMetalCommandQueue`, `wgpuTextureGetNativeMetalTexture`) *are*
bound and return null on non-Metal backends, verified in `tests/test_device.mojo`
and `tests/test_texture.mojo`. They are the interop half; the surface half is
what is missing.

**Cost: L**, and not just a binding. It needs a `CAMetalLayer` attached to the
GLFW window's `NSWindow`, which means Objective-C: expect a new `ffi/metal_layer.m`
exposing something like `void* wgpu_mojo_metal_layer_for_window(void* nswindow)`,
with `glfwGetCocoaWindow()` supplying the input. `rendercanvas-mojo` needs the
same treatment.

It cannot be verified on the Linux dev machine or on a GitHub-hosted runner with
a GPU. Sequence it when real macOS hardware is available; until then the README
should say plainly that macOS is compute-only.

**First step:** a ≤10-line probe calling `glfwGetCocoaWindow` and creating a
`CAMetalLayer`, before writing any binding code.

## Completed tiers

### Tier 2 — correctness and consistency

- **2a (WGSL language features) — void.** The "latent leak" this described
  assumed `wgpuInstanceGetWGSLLanguageFeatures` returns an array to free. It is
  an unimplemented stub; there was nothing to leak, and the binding was removed.
- **2b (`AddRef` parity) — done, bind-all.** All 22 implemented `*AddRef`
  symbols are bound (the 23rd, `wgpuExternalTextureAddRef`, is a stub), and 14
  wrapper types gained `clone()` for shared ownership. Encoders
  (`CommandEncoder`, `ComputePassEncoder`, `RenderPassEncoder`,
  `RenderBundleEncoder`) deliberately do **not** get `clone()`: they are linear
  types (`ImplicitlyDeletable where False`) that must be explicitly finished, and
  a second owner would break that contract. `tests/test_add_ref.mojo` proves the
  refcount is real by dropping the original and continuing to use the clone.
- **2c (pre-instance capability query) — done as far as upstream allows.** Only
  `wgpuGetInstanceLimits` is implemented; it is bound and exposed as
  `wgpu.instance.instance_limits()`. `wgpuGetInstanceFeatures` and
  `wgpuHasInstanceFeature` are stubs. Two latent struct layout bugs were fixed on
  the way: `WGPUSupportedInstanceFeatures` carried a `nextInChain` the header
  does not have, and `WGPUInstanceLimits` was missing `timedWaitAnyMaxCount`.

### Tier 3 — developer experience

- **`wgpuSetLogCallback` — done.** wgpu-native's log now reaches Mojo. The
  callback needs a stored C function pointer, which Mojo cannot produce, and
  wgpu-native calls it from its own threads — so `ffi/wgpu_callbacks.c` owns a
  mutex-guarded ring buffer and Mojo drains it via
  `wgpu.diagnostics.drain_log()`. Covered by `tests/test_log_bridge.mojo`.
- **Graphics-debugger capture — done.** `Device.start_graphics_debugger_capture()`
  / `stop_...()` for RenderDoc.
- **Label parity — impossible.** Every `*SetLabel` in wgpu-native v29 is a stub;
  labelling does not exist, so there is no parity to reach.

### Tier 4 — feature surface

- **SPIR-V — already worked, now tested.** `Device.create_shader_module_spirv()`
  chains `WGPUShaderSourceSPIRV`. `tests/test_spirv.mojo` exercises it with a
  hand-assembled minimal SPIR-V compute module, so the tests need no SPIR-V
  toolchain.
- **Chained descriptors — done.** `WGPURenderPassMaxDrawCount`,
  `WGPUSurfaceColorManagement`, `WGPUTextureComponentSwizzle(Descriptor)`,
  `WGPUShaderSourceGLSL`, `WGPUShaderDefine`, all with byte-size assertions.
- **External textures — excluded.** The whole object API is stubs.

### Tier 5 — coverage reporting

Done, and it is what makes the 100% above meaningful. `check-symbols` reports
`bound / (implemented − excluded)` and fails on anything unclassified.

## What to watch at the next wgpu-native bump

The stub set is specific to v29.0.0.0. A bump moves it: previously-stubbed
functions may become real (the removed wrappers can then come back), or new
stubs may appear (the gate will fail and those bindings must go). Re-run
`pixi run check-symbols` and diff before assuming anything carries over. See
also the coordinated-ABI-change requirements in the project memory.
