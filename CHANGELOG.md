# Changelog

All notable changes to wgpu-mojo are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
— with one project-specific rule: **the pinned wgpu-native ABI is part of the
public contract.** A change to it is a breaking change no matter how small
upstream's own version bump looks. wgpu-native renumbered its entire
`0x0003xxxx` SType enum in the v29.0.0.0 → v29.0.1.1 *patch* release.

## [Unreleased]

### Fixed

- **Window surfaces panicked with "Error: Unsupported Surface"** (0.3.0, and
  earlier wherever the allocator reused the freed block). `create_surface_wayland`
  and `create_surface_xlib` built the surface-source chain in `AllocGuard`s whose
  last use was reading their pointer, so ASAP destruction freed both before
  `wgpuInstanceCreateSurface` read them. They are `with`-scoped now, and
  `AllocGuard.ptr()` is gone so the pattern cannot be written again.
- **`Device.pop_error_scope()` read its message after wgpu-native freed it.**
  The callback stored the `WGPUStringView` it was given and the string was
  decoded after the callback returned; it is copied inside the callback now. It
  was also decoded byte by byte with `chr()`, which mangled any non-ASCII text
  (WGSL identifiers can be Unicode); it is decoded as UTF-8.

### Changed

- **wgpu-native's async callbacks are Mojo.** Mojo 1.1.0 can pass a >16-byte
  struct by value through `OwnedDLHandle.call` (modular#3144 no longer
  reproduces) and an `abi("C")` function's address can be stored in a C struct,
  so the adapter, device, buffer-map, queue-done and error-scope callbacks moved
  from `ffi/wgpu_callbacks.c` into `wgpu/_backend/wgpu_native/callbacks.mojo`,
  and the six pointer-taking C wrappers are gone: the loader passes each
  `*CallbackInfo` (and `WGPUSurfaceCapabilities`) straight to wgpu-native.
  `libwgpu_mojo_cb` now holds only the log ring buffer, which stays C because
  it is process-wide state and Mojo has no module-level variables.
- `check-signatures` now also compares each Mojo callback against its header
  typedef (arity and per-parameter size); `tests/test_callback_abi.mojo` pins
  the by-value `CallbackInfo` + stored-callback shape on linux-64 and osx-arm64
  without a GPU.

## [0.3.0] — 2026-10-08

Built for **stable Mojo 1.1.0** and **wgpu-native v29.0.1.1**. Breaking, because
the wgpu-native ABI pin moved (see the rule above); code that only uses the
high-level API and the core `webgpu.h` types should need no changes beyond the
renamed `WGPUNativeFeature`/extension-struct names listed below.

### Changed — breaking

- **Mojo 1.1.0.** The package is compiled with, and pinned exactly to, Mojo
  1.1.0: a `.mojoc` does not load under any other compiler version. Building
  from source needs `pixi-build-mojo` >= 0.2.6, and therefore **pixi >= 0.77.0**
  — older backends run `mojo package -o *.mojopkg`, which Mojo 1.1.0 rejects.

- **wgpu-native v29.0.0.0 → v29.0.1.1.** Per the rule above this is a breaking
  change, and this one earns it:
  - `WGPUNativeSType` is renumbered to match (`InstanceExtras` 0x00030006 →
    0x00030004, and every later value). `PipelineLayoutExtras` is gone
    upstream; immediates live on the core `WGPUPipelineLayoutDescriptor`.
  - `WGPUNativeFeature.PushConstants` is now `Immediates` (same value), and
    `UniformBufferAndStorageTextureArrayNonUniformIndexing` is now
    `StorageTextureArrayNonUniformIndexing`. `SpirvShaderPassthrough` no longer
    exists upstream. Every feature the header defines is now exposed.
  - `wgpu*SetImmediates` moved into `webgpu.h` with its last two parameters
    swapped to `(offset, data, size)`. The public `set_immediates(offset,
    size_bytes, data)` keeps its signature; the loader-level
    `*_set_immediates` methods now take `(offset, data, size)`.
  - `WGPUNativeLimits` gains `max_binding_array_sampler_elements_per_shader_stage`
    and `max_multiview_view_count`, and drops `max_push_constant_size`
    (`max_immediate_size` is on the core `WGPULimits`).
  - `WGPUInstanceBackend.DX11` is removed (wgpu dropped the backend) and
    `SECONDARY` is GL only, as in the header.
- `WGPUSurfaceConfigurationExtras.maximum_frame_latency` is renamed
  `desired_maximum_frame_latency`, and `WGPUPrimitiveStateExtras.conservative_rasterization`
  is renamed `conservative`, matching the header field names the layout gate
  now checks.

### Added

- `CommandEncoder.clear_texture()` (`wgpuCommandEncoderClearTexture`, needs
  `WGPUNativeFeature.ClearTexture`) and `Device.create_shader_module_wgsl_trusted()`
  (`wgpuDeviceCreateShaderModuleTrusted`), both new in v29.0.1.1.
- Immediates are usable end to end: `Adapter.request_device()` takes
  `required_limits` and `Device.create_pipeline_layout()` takes
  `immediate_size`. Before this, every pipeline layout was created with
  `immediate_size = 0`, so `set_immediates` could not succeed at all.
- `WGPUShaderRuntimeChecks`, `WGPUSamplerDescriptorExtras`,
  `WGPUImageSubresourceRange`, `WGPUNativeDisplayHandle`, and the remaining
  `WGPUInstanceFlag` values.
- `tests/test_native_v29_0_1.mojo` (`pixi run test-native-v29`, run in CI): an
  immediates round trip through a shader, which crashes if the argument order
  regresses, plus `clear_texture` and the trusted shader path.

### Fixed

- Five extension structs disagreed with `wgpu.h` and nothing noticed, because
  `check-struct-layout` never looked at `native_ext.mojo`.
  `WGPUInstanceExtras` was 88 bytes against the header's 112 (missing
  `displayHandle`), and `WGPURegistryReport` carried two fields the header does
  not have, which made `WGPUHubReport` and `WGPUGlobalReport` the wrong size
  too. `WGPUPipelineLayoutExtras` described a push-constant-range layout that no
  v29 header has. The gate now scans `native_ext.mojo` and also compares every
  `WGPUNativeSType`/`WGPUNativeFeature` constant against the header by value.
- `wgpu._native` was a hand-maintained copy of `native_ext.mojo` rather than a
  re-export of it, so every fix had to be made twice. It is now a shim.
- The library located `$CONDA_PREFIX` by calling `getenv` through
  `OwnedDLHandle("libc.so.6")`, a workaround for a missing `std.env` on old
  nightlies. `libc.so.6` does not exist on macOS, so there the lookup failed
  and the loader silently skipped the conda environment. It now uses
  `std.os.getenv`.
- Three copies of a null-pointer-arithmetic `sizeof` helper are replaced by
  `std.sys.size_of`.
- The conda recipe builds against Mojo 1.1.0 (it still pinned 1.0.0, so a
  package built from it would not load under the current compiler).
- Mojo 1.1.0 compatibility: `Pointer(x)` now yields an immutable origin, so the
  redundant wrappers that fed loader results into mutable slots are gone; the
  opt-in `wgpu_max` bridge imports kernel indexing from `max.gpu`, where Mojo
  1.1.0 moved it out of `std.gpu`.
- `release.yml` attached every `.conda` file under the build tree, which put a
  stale wgpu-mojo 0.2.0 and an unrelated rendercanvas-mojo 0.1.0 on the v0.2.1
  Release. The glob now reaches only the artifact directory.
- `rendercanvas-mojo`: the recipe used `mojo package … .mojopkg`, a hard error
  since Mojo 1.1.0, and `|| true` on the bridge build and install steps hid
  any failure; it now uses `mojo precompile` and fails loudly. Its
  `pixi-build-mojo` floor is raised to 0.2.6 to match the root.

- `scripts/setup-native.sh` now refuses to install into an environment that is
  not the current project's. It already required `CONDA_PREFIX` to be *set*,
  but a set prefix is not necessarily the right one: invoked as plain
  `bash scripts/setup-native.sh` instead of `pixi run bash …`, it inherited
  whatever base conda/micromamba prefix the shell carried and installed the
  callback bridge there. Nothing in the project ever looks at that path, so the
  mistake surfaced much later as `Failed to load libwgpu_mojo_cb.so` naming a
  `$CONDA_PREFIX` the program does not actually run under. The check applies
  only when the working directory owns a `.pixi/envs`, leaving the documented
  `curl … | bash` and plain-conda flows untouched; set
  `WGPU_ALLOW_FOREIGN_PREFIX=1` when the foreign target is deliberate.

## [0.2.1] — 2026-09-06

First release installable with a single `pixi add`. No API changes — everything
here is packaging, verification and documentation.

### Added

- **`pixi add wgpu-mojo` is the whole install.** The conda package ships the
  compiled Mojo package and both C callback bridges, and declares `wgpu-native`
  and `glfw` as ordinary runtime dependencies. No post-install script.
- **`check-recipe`** — builds `conda.recipe/recipe.yaml` against the working
  tree, tests included, substituting a path source for the pinned commit SHA
  that cannot exist before a commit is pushed.
- **`check-consume-channel`** — installs the built package from a local channel
  into a throwaway pixi project and runs it, with `PIXI_*` and
  `LD_LIBRARY_PATH` unset so the isolation is real. Completes a compute round
  trip where an adapter is available.
- Both gates run in CI on `linux-64` and `osx-arm64`.
- `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md` and `CODE_OF_CONDUCT.md`.
- A release guard: `release.yml` refuses to build unless the source at the
  recipe's pinned `rev` matches the tagged source outside `conda.recipe/`.

### Changed

- **The recipe no longer downloads anything.** It previously fetched a prebuilt
  `libwgpu_native` from GitHub Releases during the build, which made the result
  non-reproducible and left the package unable to declare which ABI it
  contained. `wgpu-native` now comes from conda-forge as a declared dependency,
  pinned exactly to 29.0.0.0, and `conda.recipe/build.sh` compares the installed
  `wgpu.h` byte-for-byte against the copy vendored in this repo before compiling.
- The recipe emits `lib/mojo/wgpu.mojoc` via `mojo precompile`, replacing the
  deprecated `mojo package` and its `.mojopkg`, which the current backend does
  not auto-discover.
- `libglfw_input_cb` is now built unconditionally rather than behind `|| true`.
  `wgpu.rendercanvas` is inside the package and dlopens it; shipping the package
  without the bridge failed at runtime with nothing at install time to warn.
- `scripts/setup-native.sh` no longer overwrites a conda-managed
  `libwgpu_native`. Set `WGPU_FORCE_DOWNLOAD=1` to override. It also compiles
  the bridge against this repo's vendored headers rather than a release zip's.
- The recipe builds only `linux-64` and `osx-arm64`, skipping every other
  target explicitly.
- README leads with the channel install; the `curl … | bash` step is gone from
  that path and the wgpu-native ABI pin is now documented.

### Fixed

- `glfw` was declared in `[dependencies]` — this workspace's own dev environment
  — rather than `[package.run-dependencies]`, so a downstream consumer of
  `RenderCanvas` hit a missing `libglfw.so` at runtime.

## [0.2.0] — unreleased

Never published: installable only from git, and only after running
`scripts/setup-native.sh` by hand. Its feature set is the baseline for 0.2.1.

### Added

- **`GPU` facade** (`wgpu.gpu`) — `buffer`, `write`, `compile_compute`,
  `dispatch`, `read`; a compute round trip in a handful of lines with no manual
  bind groups, pipeline layouts or lifetime pins.
- **RAII wrappers** for every GPU object, each releasing its native handle in
  `__del__`, with encoder types linear-typed so a missing `finish()`/`end()` is
  a compile error rather than a leak.
- **Strongly-typed handle newtypes** (20 of them) so a raw pointer cannot be
  passed to the wrong FFI call.
- **`RenderCanvas`** (`wgpu.rendercanvas`) — GLFW window plus wgpu surface, with
  keyboard/mouse input through a dedicated C bridge.
- **Opt-in MAX interop** (`wgpu_max`) — bridges between wgpu buffers and MAX
  `DeviceBuffer`s. Deliberately a separate top-level package so `max` stays off
  every consumer's dependency path.
- **`preflight()` and `check_symbols()`** (`wgpu.diagnostics`) — report library
  load status, wgpu-native version, ABI symbol coverage and adapter list without
  needing a GPU.
- **Examples**: headless compute, adapter enumeration, clear screen, hello
  triangle, texture sampling, GLFW input, fire simulation, and a
  plasma → 2D SDF → raymarching fragment-shader ladder.

### Verification

Gates that run on every push, on `linux-64` and `osx-arm64`, none needing a GPU:
`check-compile`, `check-symbols`, `check-struct-layout`, `check-signatures`,
and from 0.2.1 also `check-recipe` and `check-consume-channel`. Headless GPU
tests and the documented headless examples additionally run against Mesa
lavapipe in CI.

### Known limitations

Unchanged in 0.2.1:

- **macOS is compute-only.** Surface creation is implemented for Xlib and
  Wayland only; there is no `CAMetalLayer` path yet, so windowed examples do not
  run on `osx-arm64`.
- **No zero-copy MAX interop.** Every crossing is a host round trip; sharing
  allocations needs an external-memory handle that wgpu-native exposes no API
  to obtain.
- **`linux-aarch64` is not published.** Nothing in the binding is x86-specific
  and conda-forge ships wgpu-native for it, but it is untested here.

[Unreleased]: https://github.com/Hundo1018/wgpu-mojo/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Hundo1018/wgpu-mojo/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/Hundo1018/wgpu-mojo/releases/tag/v0.2.1
