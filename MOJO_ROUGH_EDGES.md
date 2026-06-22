# Mojo Language Rough Edges & Issues

Issues and rough spots encountered while building wgpu-mojo.
Useful for contributing to Mojo's development or filing issues at
https://github.com/modular/modular/issues

---

## Open Issues (tracked upstream)

### Struct-by-value ABI Corruption through OwnedDLHandle.call
- **Issue**: https://github.com/modular/modular/issues/3144
- **Status**: OPEN, assigned to dgurchenkov, no fix timeline
- **Symptom**: Passing a struct > 16 bytes by value to a C function via `OwnedDLHandle.call`
  produces corrupted data. The C side reads garbage — the 40-byte `CallbackInfo40` checksum
  mismatches 100% reproducibly (probe_09 XFAIL).
- **Root cause**: Mojo's FFI layer doesn't correctly marshal struct-by-value across the
  language boundary for structs > 16 bytes. On x86_64 SysV ABI, such structs must be passed
  on the stack (not in registers), but Mojo's dynamic dispatch doesn't handle this correctly.
  On macOS it's worse — receiving struct return values from C crashes with bus error.
- **Impact on wgpu-mojo**: Directly blocks passing `WGPURequestAdapterCallbackInfo` (40 bytes)
  and similar callback-info structs by value. This is the core reason the C callback bridge
  (`libwgpu_mojo_cb.so`) is mandatory — C receives the large struct and writes only a pointer
  result into userdata, which Mojo reads safely.
- **Workaround**: Use C bridge for any wgpu callback that passes structs > 16 bytes by value.
  Never pass such structs directly through `OwnedDLHandle.call`.

---

## Confirmed Fixed in Recent Nightly

- **`from . import module` recursive-reference error** — sub-package relative imports
  would spuriously fail. Fixed in recent nightly.

- **`MutExternalOrigin` → `MutUntrackedOrigin` rename** — Was a deprecation warning for
  all `OpaquePointer[MutExternalOrigin]` and `UnsafePointer[T, MutExternalOrigin]` FFI
  pointers. Migration is complete (`MutUntrackedOrigin` used exclusively throughout
  `wgpu/_backend/`). Rename is now settled; no more deprecation warnings in this codebase.

---

## Active Rough Edges

### 1. ASAP Destruction Forces Explicit Lifetime Pins (`_ = resource^`)
- **Context**: wgpu GPU resources submitted to queue must stay alive until GPU
  finishes executing, but Mojo's ASAP destruction drops variables at their last
  observed use — which is often before `queue_submit()` or `device.poll()`.
- **Current workaround**: `_ = pipeline^; _ = bg^; _ = buf_a^` after queue_submit
- **Desired behaviour**: Resources should be droppable after `device.poll(True)`
  returns; the compiler could infer that GPU operations serialized by a poll are
  safe to release after the poll.
- **Workaround quality**: Works but is very boilerplate-heavy and a footgun for
  newcomers who forget one pin.
- **Our fix**: `_ = resource^` pin pattern after `queue_submit`/`device.poll`;
  `wgpu/_core/session.mojo` provides a `Session` type that takes ownership and
  drops resources after `flush()`.

### 2. Mojo Functions Cannot Be Used as C Callbacks Directly
- **Context**: `def` functions in Mojo are `kgen.generator` internally, not plain
  C function pointers. You cannot extract a `void*` function pointer from a Mojo
  `def` to pass as a C callback.
- **Impact**: Any wgpu-native async operation (request_adapter_async,
  buffer_map_async, etc.) that stores a callback for later invocation requires
  a C bridge.
- **Current workaround**: `ffi/wgpu_callbacks.c` — a compiled C library with
  C-callable functions that write results into userdata structs, invoked
  synchronously via `device_poll`.
- **Issue reference**: Confirmed via ABI probe tests (`tests/abi_probes/`).
  `rebind[OpaquePointer[MutUntrackedOrigin]](fn_ptr)` does NOT yield a valid
  C function pointer.
- **Note from nightly**: CPython ABI now requires `abi("C")` effect on exported
  callbacks. Mojo may be moving toward explicit `abi("C")` as the mechanism to
  make functions C-callable.

### 3. LSP Cannot Resolve Imports in Sub-packages Without Project Root Context
- **Context**: Files inside `wgpu/_core/` doing `from wgpu._backend.*` import
  show `unable to locate module 'wgpu'` in the IDE diagnostics.
- **Root cause**: The Mojo LSP analyzes files without the `-I .` flag that the
  `mojo run` command adds. Without knowing the project root, cross-package
  absolute imports fail.
- **At compile time**: Works fine — `mojo run -I . file.mojo` resolves correctly.
- **VSCode setting**: `mojo.lsp.additionalFlags` does NOT exist in the extension.
  There is no documented way to add `-I` flags to the LSP.
- **Possible fix**: The Mojo extension should read `pixi.toml`'s `[tasks]` to
  discover the `-I` flags used in the project, or provide a
  `mojo.lsp.includePaths` setting.

### 4. `List[T].append(owned value)` — No Moved-Into-List Sugar
- **Context**: When storing non-copyable `Movable` types in a `List`, you must
  explicitly transfer with `^`: `list.append(resource^)`.
- **Impact**: Minor verbosity; can surprise users coming from Python where lists
  just hold references.
- **Not a bug**, but worth documenting for contributors writing ergonomic APIs.

### 5. No `impl Trait for Type` Syntax — Trait Conformance Must Be at Declaration
- **Context**: In Mojo, trait conformance is declared at the struct definition:
  `struct Foo(Movable, GpuResource):`. You cannot add conformance to an external
  type after the fact (unlike Rust's `impl Trait for Type`).
- **Impact**: For wgpu-mojo, this means we cannot retroactively make FFI handle
  types (`OpaquePointer`, etc.) conform to our `GpuResource` trait without
  wrapper types.
- **Workaround**: Always use newtype wrappers (our `BufferHandle`, etc.).

### 6. `@explicit_destroy` Linear Types Cannot Be Stored in Collections
- **Context**: `CommandEncoder` and `ComputePassEncoder` are marked
  `@explicit_destroy`, meaning they MUST call `finish()`/`end()` before going
  out of scope. However, storing them in a `List` or `Variant` is problematic
  because collection cleanup doesn't know to call the correct disposal method.
- **Impact**: Cannot build a "deferred encoder" queue or pool without workarounds.
- **Current state**: Linear types work well for single-owner stack usage but are
  difficult to compose into data structures.

### 7. `owned` Keyword Removed — Replaced by `var`
- **Context**: Function parameters that take ownership of a value previously used
  the `owned` keyword. In current Mojo nightly, this is `var`.
- **WRONG**: `def pin(mut self, owned resource: Buffer):`
- **CORRECT**: `def pin(mut self, var resource: Buffer):`
- **Note**: This change is NOT reflected in many tutorials and LLM training data,
  making it a common source of errors.

---

## Observations (Not Bugs, But Worth Noting)

- **No `match`/`switch` statement**: Pattern matching is done with `if`/`elif`
  chains. For GPU state machine code this creates verbose dispatch tables.
- **`rebind` semantics**: `rebind[T](value)` is a zero-cost type pun but requires
  the caller to guarantee ABI compatibility. There is no compile-time check.
  Misuse is easy in FFI contexts.
- **`mojo package` → `mojo precompile`**: Command rename, `.mojopkg` → `.mojoc`
  extension change. Affects any CI that calls these directly.
