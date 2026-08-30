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
| C functions (distinct `wgpu*`) | 190 | 226 | 84.1% |
| ↳ excluding `AddRef` (18) + `FreeMembers` (2) | 190 | 206 | 92.2% |
| Structs | 93 | 113 | 82.3% |
| Enum groups | 59 + 5 bitflags | 56 header enums | substantially complete |
| Handle newtypes | 22 | all WebGPU objects | 100% |

The headers and the shipped library agree exactly: `webgpu.h` (199) ∪ `wgpu.h` (27)
= 226 distinct symbols, and the `.so` exports exactly those 226. That makes 226 a
hard denominator rather than a guess.

The 36 unbound symbols are 18 `*AddRef`, 2 `*FreeMembers`, and 16 others.

## How coverage is measured

`scripts/check-symbols.sh` derives the *expected* set from the sources themselves —
every `"wgpu*"` string literal in `wgpu/` and `wgpu_max/`, plus every `wgpuXxx(` call
in `ffi/*.c` — and diffs it against `nm` output for the library. Nothing is
hand-maintained, so the number moves on its own as bindings are added.

Note this measures *resolvability*, not correctness: it proves every symbol the
binding names exists, not that the signature or struct layout is right. Struct
layout is still guarded only by `tests/test_structs.mojo` and the C bridge layout
contract described in `CLAUDE.md`.

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

### 2a. Latent leak: WGSL language features

`wgpuInstanceGetWGSLLanguageFeatures` is bound (`loader.mojo:1110`) but its
counterpart `wgpuSupportedWGSLLanguageFeaturesFreeMembers` is not. The call
allocates an array the caller must free. There is no high-level wrapper yet, so
nothing leaks today — but the raw loader method is reachable and leaks if used.

**Cost: S.** Bind the `FreeMembers` call; add a wrapper that frees in `__del__`,
or drop the getter until the pair is complete.

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

Today you must construct an instance to learn anything about the environment.
**Cost: S.** Bind all four together so the alloc/free pair never splits.

## Tier 3 — developer experience

| Missing | Unblocks | Cost |
|---|---|---|
| `wgpuSetLogCallback` | route wgpu-native logs into Mojo instead of raw stderr; only `set_log_level` exists today | M — needs a C bridge callback, same pattern as `wgpu_callbacks.c` |
| `wgpuDeviceStartGraphicsDebuggerCapture` / `...Stop...` | RenderDoc capture from Mojo | S — two `void` calls, no structs |
| `wgpuCommandBufferSetLabel`, `wgpuSurfaceSetLabel` | label parity; every other object has `set_label` | S |

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

Raw 190/226 will never reach 100%, because Tier 5 should never be bound. The
honest target is **coverage against a declared surface**, not against the whole
header.

Proposal: add an explicit `scripts/unbound-allowlist.txt` holding the deliberately
unbound symbols with a one-line reason each, and extend `check-symbols.sh` to
report `bound / (exported − allowlisted)`. Then:

- the number can legitimately reach 100%;
- anything newly exported by an upstream bump shows up as *unclassified* rather
  than silently widening the gap — which is the same failure mode the
  `SetPushConstants` bug came from.

Where the 36 unbound symbols land:

| Bucket | Count | Disposition |
|---|---:|---|
| The 16 "other" symbols | 15 | bind (Tiers 1–4) |
| | 1 | allowlist — `wgpuGetProcAddress` |
| `*FreeMembers` | 2 | bind (2a, 2c) |
| `*AddRef` | 18 | depends on the 2b decision |

Most of the Tier 5 table is structs, which do not appear in the symbol
denominator — only `wgpuGetProcAddress` is an allowlisted *symbol*.

So 100% is reachable under either 2b outcome:

- **bind all `AddRef`**: 190 + 15 + 2 + 18 = 225 bound, 1 allowlisted → **225/225**
- **drop the 5 bound `AddRef`**: 202 bound, 24 allowlisted → **202/202**

The choice changes the denominator, not the achievability — which is the argument
for settling 2b explicitly rather than leaving it at 5/23.

## Suggested order

1. **2a** (leak) and **2c** (instance query) — small, self-contained, no decisions.
2. **2b** — decide `AddRef` semantics and write it down; it gates Tier 4 external textures.
3. **Tier 3 `wgpuSetLogCallback`** — biggest debuggability win per unit of work.
4. **Allowlist + coverage reporting** — makes the remaining gap legible.
5. **Tier 1 macOS** — largest and highest-value, but needs macOS hardware; start with the probe.
6. **Tier 4** — on demand.
