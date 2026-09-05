# Security Policy

## Reporting a vulnerability

Report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/Hundo1018/wgpu-mojo/security/advisories/new)
for this repository. Please do not open a public issue for anything
exploitable.

Include the output of `preflight()`, the wgpu-native version you have
installed, your platform and GPU driver, and a reproducer if you have one.

Expect an acknowledgement within 7 days. This is a small volunteer-maintained
project, so please allow reasonable time for a fix before public disclosure.

## Supported versions

Only the latest released version receives fixes. There are no backports.

| Version | Supported |
|---------|-----------|
| 0.2.x   | yes       |
| < 0.2   | no        |

## What is in scope

wgpu-mojo is a binding layer. The most likely security-relevant defects are in
how it crosses the FFI boundary, and those are in scope:

- Memory-safety errors in the Mojo↔C boundary: wrong struct layouts, wrong call
  arity, missing lifetime pins, use-after-free of a released handle.
- Defects in the C bridges under `ffi/` and `rendercanvas-mojo/ffi/`.
- Anything that lets untrusted WGSL, buffer contents or descriptor input reach
  wgpu-native in a state the binding was supposed to validate.

Four automated gates cover parts of this surface — `check-symbols`,
`check-struct-layout`, `check-signatures` and `check-compile`; see
[CONTRIBUTING.md](CONTRIBUTING.md). A report showing a gap one of them should
have caught is especially useful.

## What is not in scope

- Vulnerabilities in **wgpu-native** itself, or in the GPU drivers beneath it.
  Report those to [gfx-rs/wgpu-native](https://github.com/gfx-rs/wgpu-native)
  and your driver vendor. If a wgpu-native advisory requires us to move the
  pinned ABI, open a normal issue and we will treat it as a breaking change
  (see *The ABI pin* in CONTRIBUTING.md).
- Vulnerabilities in the Mojo compiler or the MAX platform. Report those to
  [modular/modular](https://github.com/modular/modular).
- Crashes caused by passing deliberately invalid input to the low-level API.
  That layer maps 1:1 to `webgpu.h` and does not promise validation; the
  `GPU` facade and the RAII wrappers are where safety is claimed.

## Supply chain

The published conda package declares `wgpu-native` and `glfw` as ordinary
runtime dependencies resolved from conda-forge. The build script downloads
nothing: it compiles the C bridges from source in this repository and links
against the host environment. `conda.recipe/build.sh` additionally compares the
installed `wgpu.h` byte-for-byte against the copy vendored here, so the package
cannot be built against an unexpected wgpu-native revision.

CodeQL runs on this repository for the C and Python code.
