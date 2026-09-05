#!/usr/bin/env bash
# Build conda.recipe/recipe.yaml against the *working tree*.
#
# The recipe pins `source.rev` to a full commit SHA because that is what
# modular-community requires. That pin makes the recipe unverifiable before the
# commit is pushed -- which is how conda.recipe/recipe.yaml came to sit for
# months calling a deprecated CLI while every other gate stayed green, since
# nothing ever built it.
#
# This swaps only the `source:` block for a path pointing at this checkout, then
# runs the real rattler-build, tests included. Everything else -- build script,
# dependencies, ABI guard, package test -- is exercised exactly as submitted.
#
# Needs no GPU. Needs network for the conda solve.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

OUT_DIR="${1:-${TMPDIR:-/tmp}/wgpu-mojo-recipe-check}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Report on the pinned revision (informational -- it legitimately lags during
# development, and release.yml is where it becomes a hard gate).
# ---------------------------------------------------------------------------
PINNED_REV="$(sed -n 's/^  rev: "\([0-9a-f]\{40\}\)".*/\1/p' conda.recipe/recipe.yaml)"
HEAD_REV="$(git rev-parse HEAD)"
if [ -z "$PINNED_REV" ]; then
    echo "Error: conda.recipe/recipe.yaml has no 40-character source.rev pin." >&2
    exit 1
fi
if [ "$PINNED_REV" != "$HEAD_REV" ]; then
    echo "note: recipe pins $PINNED_REV, HEAD is $HEAD_REV"
    echo "      (building the working tree; bump 'rev' before tagging a release)"
fi

# ---------------------------------------------------------------------------
# Materialise a path-sourced copy of the recipe
# ---------------------------------------------------------------------------
cp -r conda.recipe "$WORK/recipe"
python3 - "$WORK/recipe/recipe.yaml" "$REPO_ROOT" <<'PY'
import re, sys

recipe_path, repo_root = sys.argv[1], sys.argv[2]
text = open(recipe_path).read()

# Replace the whole `source:` list with a single path entry. Anchored on the
# top-level key so a `source:` word inside a comment cannot match.
new_source = f"source:\n  - path: {repo_root}\n"
text, n = re.subn(
    r"^source:\n(?:[ \t]+.*\n|\n)*?(?=^\S)",
    new_source,
    text,
    count=1,
    flags=re.MULTILINE,
)
if n != 1:
    sys.exit("check-recipe.sh: could not rewrite the source: block")
open(recipe_path, "w").write(text)
PY

# ---------------------------------------------------------------------------
# Purge any cached extraction of this package
# ---------------------------------------------------------------------------
# rattler caches extracted packages by "<name>-<version>-<build_string>", and the
# build string is a hash of the *variant*, not of the contents. Rebuilding the
# same version therefore reuses a stale extraction -- including its
# info/tests/tests.yaml. A recipe that previously had no tests reports
# "all tests passed" against an empty test list, taking 0 seconds, and looks
# identical to a real pass. Observed while writing this script.
PKG_CACHE="${RATTLER_CACHE_DIR:-$HOME/.cache/rattler}/cache/pkgs"
if [ -d "$PKG_CACHE" ]; then
    RECIPE_VERSION="$(sed -n 's/^  version: "\(.*\)".*/\1/p' conda.recipe/recipe.yaml)"
    find "$PKG_CACHE" -maxdepth 1 -name "wgpu-mojo-${RECIPE_VERSION}-*" -print -exec rm -rf {} + 2>/dev/null | \
        sed 's/^/    purged stale cache entry: /' || true
fi

echo "==> Building recipe from the working tree"
echo "    output: $OUT_DIR"
mkdir -p "$OUT_DIR"

pixi exec rattler-build build \
    --recipe "$WORK/recipe/recipe.yaml" \
    -c https://conda.modular.com/max \
    -c conda-forge \
    --output-dir "$OUT_DIR"

echo ""
echo "==> Built packages:"
find "$OUT_DIR" -name '*.conda' -newermt '-1 hour' -print
