# Changelog

All notable changes to wgpu-mojo are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
— with one project-specific rule: **the pinned wgpu-native ABI is part of the
public contract.** A change to it is a breaking change no matter how small
upstream's own version bump looks. wgpu-native renumbered its entire
`0x0003xxxx` SType enum in the v29.0.0.0 → v29.0.1.1 *patch* release.

## [Unreleased]

Nothing yet.

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

[Unreleased]: https://github.com/Hundo1018/wgpu-mojo/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/Hundo1018/wgpu-mojo/releases/tag/v0.2.1
