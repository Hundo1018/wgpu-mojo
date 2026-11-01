#!/bin/bash
# Install the pinned Emscripten into build/emsdk (about 1.5 GB), unless
# EMSDK_DIR already points at an install of that version.
set -euo pipefail
source "$(dirname "$0")/web-env.sh"

if [ -x "$EMCC" ] && "$EMCC" --version 2>/dev/null | head -1 | grep -q " $EMSCRIPTEN_VERSION "; then
  echo "emsdk: Emscripten $EMSCRIPTEN_VERSION already at $EMSDK_DIR"
  exit 0
fi
if [ ! -d "$EMSDK_DIR/.git" ]; then
  git clone --quiet https://github.com/emscripten-core/emsdk.git "$EMSDK_DIR"
fi
cd "$EMSDK_DIR"
./emsdk install "$EMSCRIPTEN_VERSION" > /dev/null
./emsdk activate "$EMSCRIPTEN_VERSION" > /dev/null
"$EMCC" --version | head -1
