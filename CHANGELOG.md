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

## [0.2.0] — 2026-09-05

First release published to the [modular-community](https://repo.prefix.dev/modular-community)
channel. Targets **wgpu-native v29.0.0.0** and **Mojo 1.0.0** on `linux-64` and
`osx-arm64`.

### Added

- **Installable as a single conda package.** `pixi add wgpu-mojo` installs the
  compiled Mojo package, both C bridges, and — through the `wgpu-native` and
  `glfw` runtime dependencies — every native library needed to run. No
  post-install script.
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

Five machine gates run on every push, on `linux-64` and `osx-arm64`:

- `check-compile` — every test and example still compiles, plus a full-tree
  package build
- `check-symbols` — every FFI symbol resolves, none is an upstream
  `unimplemented!()` stub, nothing implemented is left unclassified
- `check-struct-layout` — every FFI struct's size and field count against the
  real C headers
- `check-signatures` — every FFI call's arity and void-ness against the header
  declaration
- `check-recipe` — the conda recipe builds and its package test passes

Headless GPU tests and the documented headless examples additionally run against
Mesa lavapipe in CI.

### Known limitations

- **macOS is compute-only.** Surface creation is implemented for Xlib and
  Wayland only; there is no `CAMetalLayer` path yet, so windowed examples do not
  run on `osx-arm64`.
- **No zero-copy MAX interop.** Every crossing is a host round trip; sharing
  allocations needs an external-memory handle that wgpu-native exposes no API
  to obtain.
- **`linux-aarch64` is not published.** Nothing in the binding is x86-specific
  and conda-forge ships wgpu-native for it, but it is untested here.

[Unreleased]: https://github.com/Hundo1018/wgpu-mojo/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Hundo1018/wgpu-mojo/releases/tag/v0.2.0
