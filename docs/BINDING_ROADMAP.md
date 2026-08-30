# Binding Roadmap

What is still unbound between wgpu-mojo and wgpu-native **v29.0.0.0**, why, and in
what order it is worth closing.

All numbers below are measured, not estimated — reproduce them with:

```bash
pixi run check-symbols     # symbol coverage against the shipped libwgpu_native
```

Last measured: 2026-08-30, against `ffi/lib/libwgpu_native.so` (226 exported `wgpu*` symbols).

## Where we are

| Category | Bound | Total | Coverage |
|---|---:|---:|---:|
| C functions, vs. everything exported | 162 | 226 | 71.7% |
| **C functions, vs. what upstream implements** | **162** | **187** | **86.6%** |
| ↳ of those bound, usable (no upstream stubs bound) | 162 | 162 | **100%** |
| Structs | 93 | 113 | 82.3% |
| Enum groups | 59 + 5 bitflags | 56 header enums | substantially complete |
| Handle newtypes | 22 | all WebGPU objects | 100% |

The headers and the shipped library agree exactly: `webgpu.h` (199) ∪ `wgpu.h` (27)
= 226 distinct symbols, and the `.so` exports exactly those 226.

But 226 is the wrong denominator, because **39 of those 226 are `unimplemented!()`
stubs** that abort the process when called (see "How coverage is measured"). The
real bindable surface is 187, and no stub is bound any more — so every symbol
this binding names both resolves *and* works.

The 25 unbound-but-implemented symbols are 17 `*AddRef` (a design decision, see
2b) and 8 others.

## How coverage is measured

`scripts/check-symbols.sh` derives the *expected* set from the sources themselves —
every `"wgpu*"` string literal in `wgpu/` and `wgpu_max/`, plus every `wgpuXxx(` call
in `ffi/*.c` — and diffs it against `nm` output for the library. Nothing is
hand-maintained, so the number moves on its own as bindings are added.

The script runs a second check: wgpu-native exports `unimplemented!()` stubs for
parts of `webgpu.h` it has not built. They link, so the resolution check cannot
see them — but calling one panics in Rust across the FFI boundary and **aborts
the process**, with no Mojo-level error to catch. 39 of the 226 exported symbols
are such stubs. `scripts/known-unimplemented.txt` records the ones already bound
so the gate fails on any new one.

Note what is still *not* measured: signatures and struct layout. A binding can
resolve, be implemented, and still be wrong if the argument types or struct
layout disagree with the header — as `WGPUSupportedInstanceFeatures` did, with a
spurious `nextInChain` shifting every field by 8 bytes. Layout is guarded only by
`tests/test_structs.mojo` (now with byte-size assertions for the instance
structs) and the C bridge layout contract in `CLAUDE.md`.

## Tier 0 — RESOLVED: 29 abort-on-call symbols removed

**Found while implementing Tier 2, and since fixed by removing every one.**

wgpu-native v29 exports `unimplemented!()` stubs that link cleanly and panic on
call. 29 of them are bound here and reachable through the public API:

| Group | Symbols | Exposed as |
|---|---:|---|
| `*SetLabel` — every object type | 18 | `set_label()` on ~18 wrapper types |
| Buffer mapped-range access | 3 | `wgpuBufferGetMapState`, `Read`/`WriteMappedRange` |
| Async pipeline creation | 2 | `Device.create_*_pipeline_async()` |
| Device / instance queries | 5 | incl. `wgpuDeviceGetAdapterInfo`, `wgpuInstanceWaitAny` |
| Shader compilation info | 1 | `ShaderModule.get_compilation_info()` |

Note that `BINDING_STATUS.md` lists the async-pipeline and compilation-info
entries under "✅ 全部完成". They are bound; the implementation behind them does
not exist. `tests/test_debug_groups.mojo` already carries a commented-out
`test_encoder_set_label()` with the note that the symbol is not implemented — so
one instance of this was known, but not generalised.

None of these have test coverage, which is why they stayed green.

**Resolution: removed outright.** All 29 are gone — public wrappers, loader
methods, the three C bridge paths (`wgpu_mojo_shader_get_compilation_info`,
`..._create_compute_pipeline_async`, `..._create_render_pipeline_async`) with
their callbacks and cached function pointers, the dead result structs, and the
`set_label` requirement on the `GpuResource` trait.

This is a breaking API change: `set_label()` is gone from ~18 wrapper types, as
are `Buffer.map_state()`, `Device.create_*_pipeline_async()` and
`ShaderModule.get_compilation_info()`. Nothing is lost in practice — every one
of them could only ever have aborted the caller.

`scripts/known-unimplemented.txt` is now empty and stays as the ratchet:
`check-symbols` fails if any binding resolves a stub not listed there, so
re-introducing one has to be deliberate. Verified by re-adding a stub symbol and
confirming the gate exits 1 and names it.

If upstream implements these later, re-adding them is mechanical — and the gate
will stop complaining on its own once the stubs become real code.

## Tier 1 — macOS cannot open a window

**This is the largest real gap.** `pixi.toml` declares `platforms = ["linux-64",
"osx-arm64"]` and CI builds on macOS arm64, but surface creation only supports
Xlib and Wayland. On macOS the library loads and headless compute works; anything
windowed has no path at all.

| Missing | Kind |
|---|---|
| `WGPUSurfaceSourceMetalLayer` | struct |
| `wgpuDeviceGetNativeMetalDevice`, `wgpuQueueGetNativeMetalCommandQueue`, `wgpuTextureGetNativeMetalTexture` | functions |

Only the SType enum value exists today (`types.mojo` `SurfaceSourceMetalLayer`);
there is no descriptor struct and no plumbing.

**Cost: L.** Not just a binding — it needs a `CAMetalLayer` attached to the
GLFW window's `NSWindow`, which means Objective-C. Expect a new `ffi/metal_layer.m`
compiled into the bridge alongside `wgpu_callbacks.c`, exposing something like
`void* wgpu_mojo_metal_layer_for_window(void* nswindow)`, with
`glfwGetCocoaWindow()` supplying the input. `rendercanvas-mojo` needs the same
treatment.

**Cost note:** this cannot be verified on the Linux dev machine or on a
GitHub-hosted runner with a GPU — it needs real macOS hardware. Sequence it when
that is available, and until then say plainly in the README that macOS is
compute-only.

**First step:** a ≤10-line probe that calls `glfwGetCocoaWindow` and creates a
`CAMetalLayer`, before writing any binding code.

## Tier 2 — correctness and consistency

Small, self-contained, and worth doing before any new feature surface.

### 2a. WGSL language features — VOID, not a leak

Superseded by Tier 0. `wgpuInstanceGetWGSLLanguageFeatures` is an unimplemented
stub, so it never returns an array and there is nothing to leak. The real defect
is worse: the bound loader method aborts the process if called.

Binding its `FreeMembers` counterpart would have been pointless. The getter and
`wgpuInstanceHasWGSLLanguageFeature` are recorded in
`scripts/known-unimplemented.txt`; removing them is part of the Tier 0 decision.

### 2b. `AddRef` parity — a decision, not just a binding

5 of 23 `AddRef` symbols are bound (`Adapter`, `Buffer`, `Device`, `Instance`,
`Texture`); the other 18 are not. That split is arbitrary and undocumented — it
means five wrapper types could support shared ownership and the rest cannot.

Two coherent options:

- **Bind all 23** and give every wrapper explicit clone semantics
  (`fn clone(self) -> Self` calling `AddRef`). This is the only way a user can
  hold two owners of the same GPU object, which today is impossible for most types.
- **Drop the 5** and document RAII-only, single-owner semantics, keeping
  `ArcPointer[InstanceOwner]` as the sole sharing mechanism.

Pick one and write it down. Leaving it at 5/23 is the worst of both.
**Cost: M** either way (the work is the semantics, not the FFI).

### 2c. Pre-instance capability query

| Missing | Why it matters |
|---|---|
| `wgpuGetInstanceLimits`, `wgpuGetInstanceFeatures`, `wgpuHasInstanceFeature` | query support *before* creating an instance |
| `wgpuSupportedInstanceFeaturesFreeMembers` | pairs with `GetInstanceFeatures` |
| `WGPUCompatibilityModeLimits` | struct for the above |

**Status: partially done.** Only `wgpuGetInstanceLimits` is implemented upstream
and it is now bound and exposed as `wgpu.instance.instance_limits()`, covered by
`tests/test_instance.mojo`. `wgpuGetInstanceFeatures`, `wgpuHasInstanceFeature`
and `wgpuSupportedInstanceFeaturesFreeMembers` are unimplemented stubs and are
deliberately **not** bound.

Two struct layout bugs were fixed on the way, both latent because nothing used
them: `WGPUSupportedInstanceFeatures` carried a `nextInChain` the header does not
have, and `WGPUInstanceLimits` was missing `timedWaitAnyMaxCount`.
`WGPUCompatibilityModeLimits` was added. All four now have byte-size assertions
in `tests/test_structs.mojo`.

Remaining here: nothing actionable until upstream implements the other three.

## Tier 3 — developer experience

| Missing | Unblocks | Cost |
|---|---|---|
| `wgpuSetLogCallback` | route wgpu-native logs into Mojo instead of raw stderr; only `set_log_level` exists today | M — needs a C bridge callback, same pattern as `wgpu_callbacks.c` |
| `wgpuDeviceStartGraphicsDebuggerCapture` / `...Stop...` | RenderDoc capture from Mojo | S — two `void` calls, no structs |

`wgpuCommandBufferSetLabel` and `wgpuSurfaceSetLabel` were previously listed here
as "label parity". They are stubs too, as is every other `*SetLabel` — labelling
simply does not exist in wgpu-native v29, so there is no parity to reach.

`wgpuSetLogCallback` is the one with real payoff — wgpu-native validation errors
currently surface as raw status codes with no context, which `BINDING_STATUS.md`
already flags as the weakest part of the error story.

## Tier 4 — new feature surface

Nothing here blocks existing users; take them on demand.

| Feature | Missing pieces | Cost |
|---|---|---|
| SPIR-V shaders | `wgpuDeviceCreateShaderModuleSpirV`, `WGPUShaderModuleDescriptorSpirV` | S — lets precompiled SPIR-V bypass WGSL |
| GLSL shaders | `WGPUShaderSourceGLSL`, `WGPUShaderDefine` | S |
| Texture swizzle | `WGPUTextureComponentSwizzle`, `WGPUTextureComponentSwizzleDescriptor`, `WGPUTextureBindingViewDimension`, `wgpuTextureGetTextureBindingViewDimension` | M |
| External textures | `wgpuExternalTextureRelease`, `wgpuExternalTextureSetLabel`, `WGPUExternalTextureBindingEntry`, `WGPUExternalTextureBindingLayout` | M — its `AddRef` is among the 18 unbound; settle 2b first |
| Misc descriptors | `WGPURenderPassMaxDrawCount`, `WGPUSurfaceColorManagement` | S |

## Tier 5 — deliberately unbound

These should be recorded as out of scope rather than counted as debt.

| Symbol / struct | Why not |
|---|---|
| `wgpuGetProcAddress` | the loader resolves symbols via `dlsym` directly; binding it adds nothing |
| `WGPURequestAdapterWebXROptions` | WebXR; no meaning in a native binding |
| `WGPUSurfaceSourceSwapChainPanel` | UWP-only |
| `WGPUSurfaceSourceWindowsHWND` | no `win-64` in `pixi.toml`; revisit only if Windows becomes a target |
| `WGPUSurfaceSourceAndroidNativeWindow` | same, for Android |
| `WGPUXlibDisplayHandle`, `WGPUXcbDisplayHandle`, `WGPUWaylandDisplayHandle`, `WGPUNativeDisplayHandle` | display-specific adapter enumeration only; the bound `wgpuInstanceEnumerateAdapters` path covers real use |
| the 3 Metal native-handle getters | meaningful only alongside Tier 1; sequence them there |

## Making "100%" mean something

Raw 162/226 will never reach 100%: 39 of those symbols are upstream stubs that
should never be bound, and a handful more (`wgpuGetProcAddress`, WebXR, UWP) are
meaningless in a native binding. The honest denominator is **what upstream
actually implements, minus what we deliberately exclude**.

That number already exists and is enforced. `scripts/known-unimplemented.txt`
keeps stubs out; the remaining question is only the 25 unbound-but-implemented
symbols:

| Bucket | Count | Disposition |
|---|---:|---|
| `*AddRef` | 17 | depends on the 2b decision |
| Metal native-handle getters | 3 | bind with Tier 1 |
| `wgpuSetLogCallback` | 1 | Tier 3 |
| Graphics-debugger capture | 2 | Tier 3 |
| SPIR-V shader modules | 1 | Tier 4 |
| `wgpuTextureGetTextureBindingViewDimension` | 1 | Tier 4 |

So 187/187 is reachable, under either 2b outcome:

- **bind all `AddRef`**: 162 + 8 + 17 = **187/187**
- **drop the 5 already bound**: 157 + 8 = 165 bound, denominator 165 → **165/165**

The choice changes the denominator, not the achievability — which is the argument
for settling 2b explicitly rather than leaving it at 5/22 implemented.

Worth adding when someone next touches the gate: report `bound / (implemented −
deliberately-excluded)` directly in `check-symbols` output, so an upstream bump
surfaces newly-exported symbols as *unclassified* rather than silently widening
the gap. That is the same failure mode the `SetPushConstants` bug came from.

## Suggested order

1. ~~**2a** and **2c**~~ — done as far as upstream allows: `instance_limits()`
   shipped, two struct layouts fixed, the rest blocked by upstream stubs.
2. ~~**Tier 0**~~ — done: all 29 abort-on-call symbols removed, ratchet in place.
3. **2b** — decide `AddRef` semantics and write it down. Now the single largest
   remaining item: 17 of the 25 unbound-but-implemented symbols are `AddRef`.
4. **Tier 3 `wgpuSetLogCallback`** — biggest debuggability win per unit of work.
5. **Tier 1 macOS** — largest and highest-value, but needs macOS hardware; start with the probe.
6. **Tier 4** — on demand.
