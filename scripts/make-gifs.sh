#!/usr/bin/env bash
# Assemble the README showcase GIFs from raw RGBA frames produced by
# `pixi run render-gifs` (tools/render_shader_gif.mojo). The renderer writes
# deterministic, GPU-rendered frames to /tmp/<name>.rgba; this turns each into
# an animated GIF with a per-clip palette for quality.
#
# Why raw frames instead of a screen recording: the wgpu window presents via a
# GPU flip that x11grab cannot capture (the recorded stream is frozen), so the
# frames are rendered off-screen and read back from the GPU instead.
set -euo pipefail

W=${W:-480}
H=${H:-270}
FPS=${FPS:-16}
GIF_W=${GIF_W:-384}          # downscale width to keep the README GIFs small
ASSETS=${ASSETS:-assets}

for name in plasma metaballs raymarch; do
    raw="/tmp/${name}.rgba"
    out="${ASSETS}/${name}.gif"
    if [[ ! -s "$raw" ]]; then
        echo "missing $raw — run 'pixi run render-gifs' first" >&2
        exit 1
    fi
    ffmpeg -y -f rawvideo -pix_fmt rgba -s "${W}x${H}" -framerate "$FPS" -i "$raw" \
        -vf "scale=${GIF_W}:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a" \
        "$out" 2>/dev/null
    echo "built $out ($(stat -c%s "$out") bytes)"
done
