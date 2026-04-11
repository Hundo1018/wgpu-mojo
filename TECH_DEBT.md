# wgpu-mojo Technical Debt

## Current Verified State

- End-to-end GPU compute is working: `pixi run example-compute` completes successfully and validates all 1024 output elements.
- Non-GPU test tasks are stable: `pixi run test` passes.
- Several GPU-facing tests still crash, but the failures cluster around the same ownership and lifetime model rather than unrelated API bugs.

## P0: Lifetime Model Is Unsound For GPU Objects

### Problem

Mojo's ASAP destruction releases `Movable` values immediately after their last visible use. This is incompatible with the current wrapper design because most APIs extract raw handles and then rely on the original wrapper object remaining alive implicitly.

This causes resources to be destroyed before wgpu-native consumes them, often at:

- bind group creation
- pipeline recording
- queue submission
- buffer unmap or map-read

### Evidence

- `examples/compute_add.mojo` only became stable after explicit lifetime pins such as `_ = pipeline^`, `_ = bg^`, `_ = buf_c^`, `_ = device^`.
- `tests/test_buffer.mojo` fails at `wgpuBufferUnmap` because the staging buffer is destroyed too early.
- `tests/test_bind_group.mojo` extracts `buf.handle()` and `bgl.handle()` without keeping the owners alive through bind group creation.
- `tests/test_command_encoder.mojo` records copy commands using raw handles while the source and destination buffers can die before submit.

### Affected Files

- [wgpu/device.mojo](wgpu/device.mojo)
- [wgpu/buffer.mojo](wgpu/buffer.mojo)
- [wgpu/bind_group.mojo](wgpu/bind_group.mojo)
- [wgpu/pipeline.mojo](wgpu/pipeline.mojo)
- [wgpu/command.mojo](wgpu/command.mojo)
- [wgpu/texture.mojo](wgpu/texture.mojo)
- [wgpu/instance.mojo](wgpu/instance.mojo)
- [tests/test_buffer.mojo](tests/test_buffer.mojo)
- [tests/test_bind_group.mojo](tests/test_bind_group.mojo)
- [tests/test_command_encoder.mojo](tests/test_command_encoder.mojo)
- likely the rest of the GPU tests that pass raw handles into later commands

### Recommended Direction

Short term:

- Add explicit lifetime pins in GPU tests and examples immediately after the last GPU-visible use, not after the last Mojo method call.
- Treat any use of `.handle()` as a potential lifetime hazard.

Medium term:

- Redesign wrappers so parent ownership is preserved structurally, not manually.
- Candidate approaches:
  - Store parent handles or owner wrappers inside dependent wrappers.
  - Replace raw-handle-taking APIs with wrapper-taking APIs where practical.
  - Introduce small helper objects for submit-scoped resource retention.

Success condition:

- GPU tests pass without scattered `_ = var^` pins in every test body.

## P0: Raw Handle API Encourages Unsafe Call Sites

### Problem

Most high-level APIs still accept raw `WGPU*Handle` values instead of the RAII wrapper types. That means the caller must manually keep the owner alive, which is easy to forget and hard to review.

Examples:

- `Device.queue_write_buffer(buffer: WGPUBufferHandle, ...)`
- `CommandEncoder.copy_buffer_to_buffer(src: WGPUBufferHandle, dst: WGPUBufferHandle, ...)`
- `ComputePipeline.get_bind_group_layout(...) -> WGPUBindGroupLayoutHandle`

### Risk

- The API surface looks safe but behaves like borrowed raw FFI.
- Tests and examples appear idiomatic while still being memory-lifetime fragile.

### Recommended Direction

- Prefer overloads or replacements that accept wrapper types like `Buffer`, `BindGroupLayout`, `Texture`, `ComputePipeline`.
- Keep low-level raw handle methods available, but move them behind an explicitly unsafe or low-level path.

## P0: README Overstates RAII Safety

### Problem

[README.md](README.md) currently says GPU objects are automatically released when they go out of scope and that no manual cleanup is needed. That is only partially true in this codebase because object lifetime is currently too eager for GPU command submission patterns.

### Risk

- Users will write examples that compile, then fail nondeterministically or during submit.
- Contributors may assume lifetime bugs are impossible and debug the wrong layer.

### Recommended Direction

- Update the README to state that current wrappers are RAII-based but lifetime-sensitive under Mojo ASAP destruction.
- Document the temporary workaround pattern until the wrapper API is redesigned.

## P1: GPU Test Coverage Exists But Is Not Yet Stable Coverage

### Problem

There are many GPU-oriented test files, but several are currently crash-prone. As a result, nominal coverage is higher than effective verified coverage.

Likely unstable or needing lifetime fixes:

- [tests/test_buffer.mojo](tests/test_buffer.mojo)
- [tests/test_bind_group.mojo](tests/test_bind_group.mojo)
- [tests/test_command_encoder.mojo](tests/test_command_encoder.mojo)
- [tests/test_compute_pipeline.mojo](tests/test_compute_pipeline.mojo)
- [tests/test_pipeline_layout.mojo](tests/test_pipeline_layout.mojo)
- [tests/test_render_pipeline.mojo](tests/test_render_pipeline.mojo)
- [tests/test_query_set.mojo](tests/test_query_set.mojo)
- [tests/test_texture.mojo](tests/test_texture.mojo)
- [tests/test_debug_groups.mojo](tests/test_debug_groups.mojo)

### Recommended Direction

- First pass: make each test pass with explicit lifetime pins.
- Second pass: factor out helper patterns so tests exercise the API rather than encoding object-lifetime folklore.
- Third pass: separate smoke tests from semantic validation tests so failures narrow quickly.

## P1: Descriptor And Temporary Data Lifetimes Are Still Easy To Misuse

### Problem

Several APIs rely on temporary allocations or temporary strings whose lifetime must cover an FFI call exactly. This has already shown up in shader entry-point strings and array-backed descriptors.

### Risk Areas

- descriptor structs holding pointers to heap allocations created in the caller
- `String` to `WGPUStringView` conversions
- `List.unsafe_ptr()` passed into descriptors or queue writes
- temporary allocations freed immediately after wrapper creation

### Recommended Direction

- Add helper constructors for common descriptors so pointer-backed fields are assembled in one place.
- Audit every `unsafe_ptr()`, `alloc[...]`, and `str_to_sv(...)` call in GPU paths.

## P1: Each Wrapper Recreates WGPULib Repeatedly

### Problem

Many `create_*` methods instantiate a new `WGPULib()` for each returned wrapper instead of sharing an existing library owner.

### Risk

- Not currently the main correctness bug, but it is wasteful and makes ownership relationships harder to reason about.
- It obscures which wrapper actually owns or borrows the dynamic library state.

### Recommended Direction

- Define one clear ownership model for `WGPULib` across `Instance`, `Device`, and child resources.
- Either share a common library holder or store a lightweight borrowed reference strategy consistently.

## P2: Root Directory Contains Built Artifacts

### Problem

The repo root contains generated binaries such as `compute_add`, `enumerate_adapters`, `test_debug_groups`, `test_query_set`, and `test_render_pipeline`.

### Risk

- Noise in git status and workspace browsing.
- Easier to mistake generated binaries for source files.

### Recommended Direction

- Add or verify ignore rules for generated executables.
- Prefer a dedicated build output directory if the Mojo toolchain allows it.

## Suggested Execution Order

1. Stabilize GPU tests with explicit lifetime pins.
2. Update README so current constraints are stated honestly.
3. Refactor the public API to prefer wrapper-based parameters over raw handles.
4. Introduce reusable helpers for descriptor and resource lifetime management.
5. Simplify `WGPULib` ownership and cleanup model.

## Definition Of Done For This Debt List

This document can be considered mostly resolved when:

- all GPU tests in `pixi.toml` pass reliably on a real adapter
- examples no longer need scattered manual lifetime pins
- README accurately describes ownership and lifetime behavior
- high-level APIs no longer force callers into raw-handle lifetime management