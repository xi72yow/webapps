#!/usr/bin/env bash
# builds the electron-based teams package inside a container,
# nothing is installed on the host
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/electron"
OUT_DIR="$ROOT_DIR/dist"
IMAGE="webapps-electron-builder"

# stale artifacts would otherwise be copied into dist/ and end up in the apt pool
rm -rf "$APP_DIR/dist"
mkdir -p "$OUT_DIR" "$ROOT_DIR/.cache/electron" "$ROOT_DIR/.cache/electron-builder"

# ci appends the run number so every release outranks the previous one
# without anyone editing package.json. '+' keeps dpkg ordering intact and
# stays valid semver, unlike a '-' suffix which would read as a prerelease
DIST_ARGS=""
if [ -n "${BUILD_NUMBER:-}" ]; then
  BASE=$(node -p "require('$APP_DIR/package.json').version" 2>/dev/null \
         || sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$APP_DIR/package.json" | head -1)
  DIST_ARGS="-- --config.extraMetadata.version=${BASE}+${BUILD_NUMBER}"
fi

podman build -t "$IMAGE" -f "$APP_DIR/build/Containerfile" "$APP_DIR/build/"

# electron and electron-builder pull binaries, so the caches are persisted
# the repo root is mounted, not just electron/, because extraFiles pulls the
# tabler license from ../icons
podman run --rm \
    -v "$ROOT_DIR":/src:Z \
    -v "$ROOT_DIR/.cache/electron":/root/.cache/electron:Z \
    -v "$ROOT_DIR/.cache/electron-builder":/root/.cache/electron-builder:Z \
    -w /src/electron \
    "$IMAGE" \
    bash -c "npm install && npm run dist $DIST_ARGS"

cp "$APP_DIR"/dist/*.deb "$OUT_DIR/"
for f in "$APP_DIR"/dist/*.deb; do
  echo "  -> dist/$(basename "$f")"
done
