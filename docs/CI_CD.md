# CI/CD Guide

How wgpu-mojo is tested and released on GitHub, **what cannot run on GitHub-hosted
runners**, and how to set up the missing pieces yourself.

## Pipeline overview

| Workflow | File | Trigger | What it does |
|---|---|---|---|
| **CI** | [.github/workflows/ci.yml](../.github/workflows/ci.yml) | push/PR to `main`/`develop` | Non-GPU tests + compile-check on Linux & macOS arm64; headless GPU tests via lavapipe; conda recipe build + channel install |
| **Package Consume** | [.github/workflows/consume.yml](../.github/workflows/consume.yml) | push/PR + weekly + manual | Installs wgpu-mojo as a package into an isolated project and runs it |
| **Release** | [.github/workflows/release.yml](../.github/workflows/release.yml) | tag `v*` + manual | Builds a `.conda` per platform and attaches it to a GitHub Release |
| **Stable Mojo Tracking** | [.github/workflows/stable-tracking.yml](../.github/workflows/stable-tracking.yml) | weekly Mon 06:17 UTC + manual | Updates to the latest stable Mojo release (`max` channel), tests, auto-commits `pixi.lock` or files an issue |

```
                ┌─ ci.yml ──────── test (linux, macos) + gpu-software (lavapipe)
 push / PR ─────┤                  package (recipe build → channel install, linux + macos)
                └─ consume.yml ─── consume-path (pixi add --path, this commit)
                                   consume-git  (pixi add --git, documented flow)*  *non-PR

 tag v* ───────── release.yml ──── build .conda (linux-64, osx-arm64) → GitHub Release

 cron  ────────── stable-tracking.yml ─ bump pixi.lock to latest stable Mojo
```

## What runs on GitHub vs. what does not

| Concern | GitHub-hosted free runner | Self-hosted / local only |
|---|---|---|
| Non-GPU unit tests (`pixi run test`) | ✅ ubuntu + macos-14 | — |
| Compile-check / API drift (`check-compile`) | ✅ | — |
| Package consume test (`pixi add`) | ✅ `consume.yml` | — |
| Headless GPU compute (instance/device/buffer/compute) | ✅ via **lavapipe** (software Vulkan, Linux) | also real GPU |
| Windowed / display tests (triangle, fire-sim, glfw input) | ❌ needs display + GPU | ✅ self-hosted / local (Xvfb) |
| Real-hardware GPU validation, multi-vendor (NVIDIA/AMD/Metal) | ❌ no physical GPU | ✅ self-hosted runner (below) |
| Conda recipe build + package test | ✅ `ci.yml` job `package` | — |
| Install from a conda channel into a fresh project | ✅ `ci.yml` job `package` | also real GPU |
| Conda package build + Release | ✅ `release.yml` | — |

The first column is fully automated. The rest of this document is the guide for the
second column — the parts GitHub's free runners cannot do.

## Software GPU on free runners (lavapipe)

GitHub-hosted runners have no GPU, but Mesa's **lavapipe** is a CPU implementation of
Vulkan. wgpu-native's Vulkan backend enumerates it as an adapter, so the headless
compute paths run without hardware:

```bash
sudo apt-get install -y mesa-vulkan-drivers vulkan-tools libvulkan1
export VK_ICD_FILENAMES=$(ls /usr/share/vulkan/icd.d/lvp_icd*.json | head -1)
export LIBGL_ALWAYS_SOFTWARE=1
pixi run test-compute        # runs on the CPU "GPU"
```

This is what the `gpu-software` job in `ci.yml` does. It is `continue-on-error: true`
until we confirm lavapipe covers every feature these tests touch; flip that flag off
once it is reliably green to make it a required check. **Display/windowed tests are
intentionally excluded** — lavapipe has no swapchain/present path here.

## Self-hosted GPU runner (real hardware + windowed tests)

For real-GPU validation across vendors and for the windowed examples, register a
self-hosted runner on a machine with a GPU.

1. **Register the runner** (repo → Settings → Actions → Runners → New self-hosted
   runner) and give it the label `gpu` during configuration:
   ```bash
   ./config.sh --url https://github.com/Hundo1018/wgpu-mojo --token <TOKEN> --labels gpu
   ./run.sh    # or install as a service: sudo ./svc.sh install && sudo ./svc.sh start
   ```
2. **Install GPU drivers + a display server** on that machine:
   - Linux: `mesa-vulkan-drivers` + `libvulkan1` (or NVIDIA proprietary drivers), plus
     `xvfb` for headless windowed tests.
   - macOS self-hosted: Metal is built in; a logged-in GUI session is needed for
     on-screen windows.
3. **Add a GPU workflow** that targets the runner. Create
   `.github/workflows/gpu-tests.yml`:

   ```yaml
   name: GPU Tests (self-hosted)
   on:
     workflow_dispatch:
     schedule:
       - cron: "0 6 * * *"   # nightly hardware validation
   jobs:
     gpu:
       runs-on: [self-hosted, gpu]
       steps:
         - uses: actions/checkout@v4
         - uses: prefix-dev/setup-pixi@v0.8.0
           with:
             activate-environment: true
         - run: bash scripts/setup-native.sh
         - name: Full GPU test suite
           run: |
             pixi run test-instance
             pixi run test-device
             pixi run test-buffer
             pixi run test-shader
             pixi run test-bind-group
             pixi run test-compute
             pixi run test-texture
             pixi run test-texture-sample
             pixi run test-sampler
             pixi run test-command
             pixi run test-pipeline-layout
             pixi run test-error-scope
             pixi run test-render-bundle
         - name: Windowed examples (headless via Xvfb)
           run: |
             xvfb-run -a pixi run example-clear
             xvfb-run -a pixi run example-triangle
   ```

   Keep this workflow off `pull_request` from forks — self-hosted runners must not
   execute untrusted PR code.

## Local GPU testing

On a workstation with a GPU, run any GPU task directly:

```bash
pixi run build-callbacks       # one-time: native lib + C bridges
pixi run test-buffer           # or test-compute, test-texture, ...
pixi run example-fire-sim      # windowed demo
```

To force the software adapter locally (reproduce the CI `gpu-software` job):

```bash
export VK_ICD_FILENAMES=$(ls /usr/share/vulkan/icd.d/lvp_icd*.json | head -1)
export LIBGL_ALWAYS_SOFTWARE=1
pixi run test-compute
```

## Releasing a version

The package is built from [conda.recipe/recipe.yaml](../conda.recipe/recipe.yaml)
with rattler-build. It contains the compiled `wgpu` package and both C bridges;
`libwgpu_native` and `libglfw` are **not** bundled — they are declared runtime
dependencies resolved from conda-forge, which is what makes `pixi add wgpu-mojo`
sufficient on its own without making this repo the distributor of someone else's
binaries.

The recipe's `source` is a git URL plus a full commit SHA, because
modular-community requires one. A commit cannot contain its own hash, so pinning
takes an extra commit:

1. Move `Unreleased` items into a new version heading in
   [CHANGELOG.md](../CHANGELOG.md).
2. Bump `version` in **both** [pixi.toml](../pixi.toml) and
   [conda.recipe/recipe.yaml](../conda.recipe/recipe.yaml). Commit and push.
3. Set `context.rev` in the recipe to the SHA of that pushed commit. Commit as
   `chore: pin recipe rev for vX.Y.Z` and push.
4. Tag and push:
   ```bash
   git tag v0.3.0
   git push origin v0.3.0
   ```

`release.yml` then checks two things before building: that the tag matches
`context.version`, and that the source tree at `context.rev` is identical to the
tagged source outside `conda.recipe/`. The second guard is what keeps the
one-commit offset honest — without it the released package could be built from
source that was never tagged.

`workflow_dispatch` runs the build steps as a dry run (no Release is published).

### Validating the recipe without pushing

The pinned SHA makes the recipe unverifiable before the commit exists, which is
how it once sat for months still calling the deprecated `mojo package` CLI while
every other gate stayed green. Two tasks close that:

```bash
pixi run check-recipe            # swaps in a path source, builds, runs the package test
pixi run check-consume-channel   # installs the result into a throwaway project and runs it
```

`check-consume-channel` creates a fresh pixi project in a temp directory with no
repo on the path, no `-I` flag and no `ffi/lib`, so it fails if the package is
not self-contained. On a machine with an adapter it also completes a real
compute round trip. Both run in CI's `package` job on Linux and macOS.

### Publishing to the modular-community channel

`pixi add wgpu-mojo` resolves through
[modular-community](https://github.com/modular/modular-community). To publish a
release there, open a PR against that repository adding
`recipes/wgpu-mojo/recipe.yaml` — a copy of this repo's
`conda.recipe/recipe.yaml` — together with `test_package.mojo`. A maintainer
applies the `OK to test` label to run their build. Their CI builds on
`linux-64`, `linux-aarch64` and `osx-arm64`; the recipe's `skip:` expression
declines the platforms this project does not test.

## Two build mechanisms (don't conflate them)

- **`pixi-build-mojo`** (configured under `[package.build]` in `pixi.toml`) is what
  `pixi add --git`/`--path` triggers. It packages **only the compiled `wgpu` package** — it does
  **not** bundle native `.so` files, so consumers still run `setup-native.sh`. This is
  the path `consume.yml` exercises and the README documents.

  Its version constraint must stay a **range** (`>=0.1,<0.3`), never a single minor.
  Every pixi release provides exactly one `pixi-build-api-version` virtual package
  and every backend minor demands a specific one — 0.1.x needs api `>=4,<5`
  (pixi ~0.70), 0.2.x needs `>=6,<7` (pixi >=0.72). So pinning one backend minor
  silently pins the *consumer's* pixi version: while `pixi.toml` said `0.1.*`,
  `pixi add wgpu-mojo` failed on every current pixi with
  *"could not initialize the build-backend … no candidates were found"*, and CI
  stayed green only because both consume jobs pinned pixi v0.70.2. `consume-git`
  is now matrixed over both ends of the range to keep that honest.
- **rattler-build** (`conda.recipe/recipe.yaml`) builds the **published `.conda`**:
  the compiled `wgpu` package plus both C bridges, with `wgpu-native` and `glfw`
  as declared dependencies. Installing it needs no post-install step. This is the
  path `release.yml` and the modular-community channel use, and the one CI's
  `package` job gates.

## One-time GitHub repository setup

1. **Enable Actions:** repo → Settings → Actions → General → allow workflows.
2. **Branch protection** (Settings → Branches → add rule for `main`), require these
   status checks before merge:
   - `Test (ubuntu-latest)`
   - `Test (macos-14)`
   - `Consume path (ubuntu-latest)`
   - `Consume path (macos-14)`
   - `Conda package (ubuntu-latest)`
   - `Conda package (macos-14)`

   Add `Headless GPU (lavapipe)` once it is consistently green.
3. **Stable-tracking workflow permissions:** `stable-tracking.yml` already declares
   `contents: write` and `issues: write`; ensure Settings → Actions → General →
   Workflow permissions is set to "Read and write permissions" so it can commit the
   lock bump and file issues.
