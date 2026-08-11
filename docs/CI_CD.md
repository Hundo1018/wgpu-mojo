# CI/CD Guide

How wgpu-mojo is tested and released on GitHub, **what cannot run on GitHub-hosted
runners**, and how to set up the missing pieces yourself.

## Pipeline overview

| Workflow | File | Trigger | What it does |
|---|---|---|---|
| **CI** | [.github/workflows/ci.yml](../.github/workflows/ci.yml) | push/PR to `main`/`develop` | Non-GPU tests + compile-check on Linux & macOS arm64; headless GPU tests via lavapipe |
| **Package Consume** | [.github/workflows/consume.yml](../.github/workflows/consume.yml) | push/PR + weekly + manual | Installs wgpu-mojo as a package into an isolated project and runs it |
| **Release** | [.github/workflows/release.yml](../.github/workflows/release.yml) | tag `v*` + manual | Builds a `.conda` per platform and attaches it to a GitHub Release |
| **Stable Mojo Tracking** | [.github/workflows/stable-tracking.yml](../.github/workflows/stable-tracking.yml) | weekly Mon 06:17 UTC + manual | Updates to the latest stable Mojo release (`max` channel), tests, auto-commits `pixi.lock` or files an issue |

```
                ┌─ ci.yml ──────── test (linux, macos) + gpu-software (lavapipe)
 push / PR ─────┤
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

The package is published as a self-contained `.conda` (it bundles `libwgpu_native`,
the compiled C bridges, and `wgpu.mojopkg`) built from
[conda.recipe/recipe.yaml](../conda.recipe/recipe.yaml) with rattler-build.

1. Bump the version in **both** [pixi.toml](../pixi.toml) and
   [conda.recipe/recipe.yaml](../conda.recipe/recipe.yaml) (`context.version`).
2. Tag and push:
   ```bash
   git tag v0.3.0
   git push origin v0.3.0
   ```
3. `release.yml` verifies the tag matches the recipe version, builds `linux-64` and
   `osx-arm64` packages, and attaches them to the GitHub Release. No secrets are
   required — the built-in `GITHUB_TOKEN` publishes the Release.

`workflow_dispatch` runs the build steps as a dry run (no Release is published).

Dry-run a build locally:

```bash
pixi exec rattler-build build \
  --recipe conda.recipe/recipe.yaml \
  -c https://conda.modular.com/max -c conda-forge \
  --output-dir /tmp/out
```

## Two build mechanisms (don't conflate them)

- **`pixi-build-mojo`** (configured under `[package.build]` in `pixi.toml`) is what
  `pixi add --git`/`--path` triggers. It packages **only `wgpu.mojopkg`** — it does
  **not** bundle native `.so` files, so consumers still run `setup-native.sh`. This is
  the path `consume.yml` exercises and the README documents.
- **rattler-build** (`conda.recipe/recipe.yaml`) builds a **self-contained `.conda`**
  with the native libs bundled. This is the path `release.yml` uses.

## One-time GitHub repository setup

1. **Enable Actions:** repo → Settings → Actions → General → allow workflows.
2. **Branch protection** (Settings → Branches → add rule for `main`), require these
   status checks before merge:
   - `Test (ubuntu-latest)`
   - `Test (macos-14)`
   - `Consume path (ubuntu-latest)`
   - `Consume path (macos-14)`

   Add `Headless GPU (lavapipe)` once it is consistently green.
3. **Stable-tracking workflow permissions:** `stable-tracking.yml` already declares
   `contents: write` and `issues: write`; ensure Settings → Actions → General →
   Workflow permissions is set to "Read and write permissions" so it can commit the
   lock bump and file issues.
