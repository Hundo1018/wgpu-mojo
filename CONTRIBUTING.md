# Contributing to wgpu-mojo

Thanks for taking an interest. This document covers the things that are specific
to this project — the ABI pin, the verification gates, and the release process.
Everything else is ordinary GitHub workflow.

## Getting set up

```bash
git clone https://github.com/Hundo1018/wgpu-mojo
cd wgpu-mojo
pixi install
pixi run build-callbacks   # downloads wgpu-native + compiles the C bridges
pixi run test              # non-GPU unit tests, no hardware needed
```

`build-callbacks` reads the pinned wgpu-native version from
[`ffi/wgpu-native-meta/wgpu-native-git-tag`](ffi/wgpu-native-meta/wgpu-native-git-tag).
It refuses to run if that file, `scripts/setup-native.sh` and
`loader.mojo`'s `_WGPU_NATIVE_VERSION` disagree — see *The ABI pin* below.

## The verification gates

A change is ready when these pass. None of them needs a GPU:

```bash
pixi run test                 # non-GPU unit tests
pixi run check-compile        # every test and example still compiles
pixi run check-symbols        # FFI symbols resolve, and none is an upstream stub
pixi run check-struct-layout  # every FFI struct's size + field count vs the headers
pixi run check-signatures     # every FFI call's arity + void-ness vs the headers
pixi run check-recipe         # the conda recipe builds and its package test passes
```

They exist because compile-time success proves very little across an FFI
boundary: a wrong struct layout, a wrong arity, or a symbol upstream has renamed
all compile, link, and then corrupt memory or abort at the first call. If you
add or change an FFI declaration, the relevant gate must cover it — if it
cannot, say so in the PR rather than working around the check.

`check-recipe` and `check-consume-channel` are slower than the rest (they solve
and build a conda environment) and need network access, so run them when you
touch packaging, dependencies, or anything under `ffi/`.

If you have a GPU and a display server, also run the hardware tests
(`pixi run test-compute`, `pixi run hello`, and any example you touched). CI
covers the headless subset against Mesa lavapipe, not the windowed paths.

## The ABI pin

wgpu-native's version numbers do not mean what they look like. The
v29.0.0.0 → v29.0.1.1 **patch** release renumbered the entire `0x0003xxxx`
SType enum. A mismatched library still loads and still runs — it just misreads
every extras chain, silently.

So the pinned version is exact, and it is recorded in four places that must
always agree:

| Where | What it pins |
|---|---|
| `ffi/wgpu-native-meta/wgpu-native-git-tag` | canonical record of the pinned ABI |
| `scripts/setup-native.sh` (`WGPU_TAG`) | what a developer downloads |
| `wgpu/_backend/wgpu_native/loader.mojo` (`_WGPU_NATIVE_VERSION`) | what the runtime reports |
| `conda.recipe/recipe.yaml` (`wgpu_native_version`) | what the package depends on |

`setup-native.sh` compares the first three and refuses to run on a mismatch.
`conda.recipe/build.sh` goes further and compares the installed
`$PREFIX/include/wgpu.h` byte-for-byte against the copy vendored at
`ffi/include/webgpu/wgpu.h`, so the package cannot be built against a header it
was not written for.

Bumping the ABI is a breaking change. It means updating all four, re-vendoring
`ffi/include/webgpu/*.h`, re-checking the SType and feature constants in
`wgpu/_backend/wgpu_native/native_ext.mojo`, and a major/minor version bump —
never a patch.

## Commit and PR conventions

- Conventional-commit subjects (`feat:`, `fix:`, `docs:`, `build:`, `ci:`,
  `refactor:`, `chore:`), with `!` for breaking changes.
- Write the *why* in the body. The commit log here is used as an engineering
  record — several commits document upstream behaviour that is recorded nowhere
  else.
- Fill in [the PR template](.github/pull_request_template.md), including which
  gates you ran.

## Releasing

1. Update [`CHANGELOG.md`](CHANGELOG.md): move `Unreleased` items under the new
   version heading.
2. Bump `version` in **both** [`pixi.toml`](pixi.toml) and
   [`conda.recipe/recipe.yaml`](conda.recipe/recipe.yaml).
3. Commit and push.
4. Set `rev` in `conda.recipe/recipe.yaml` to the SHA of that pushed commit,
   commit as `chore: pin recipe rev for vX.Y.Z`, and push.
5. Tag `vX.Y.Z` and push the tag. `release.yml` verifies that the tag matches
   the recipe version and that the pinned `rev`'s source tree matches the tag's,
   then builds and attaches the `.conda` artifacts to a GitHub Release.
6. To publish to the modular-community channel, open a PR against
   [modular/modular-community](https://github.com/modular/modular-community)
   adding `recipes/wgpu-mojo/recipe.yaml` — a copy of this repo's
   `conda.recipe/recipe.yaml`, plus `test_package.mojo` — and let a maintainer
   apply the `OK to test` label.

Step 4 exists because modular-community requires a full commit SHA rather than
a tag, and a commit cannot contain its own hash. The recipe therefore points one
commit behind the tag; `release.yml` checks that the difference is confined to
the recipe itself.

## Reporting bugs

Include the output of `preflight()`:

```mojo
from wgpu.diagnostics import preflight
print(preflight())
```

It reports the library search path and load status, the wgpu-native version
actually loaded, ABI symbol coverage, and every adapter found — which is the
first thing anyone will ask for.
