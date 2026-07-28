#!/usr/bin/env bash
# builds the electron-based teams package inside a container,
# nothing is installed on the host
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/electron"
OUT_DIR="$ROOT_DIR/dist"
IMAGE="webapps-electron-builder"

mkdir -p "$OUT_DIR" "$ROOT_DIR/.cache/electron" "$ROOT_DIR/.cache/electron-builder"

podman build -t "$IMAGE" -f "$APP_DIR/build/Containerfile" "$APP_DIR/build/"

# electron and electron-builder pull binaries, so the caches are persisted
podman run --rm \
    -v "$APP_DIR":/src:Z \
    -v "$ROOT_DIR/.cache/electron":/root/.cache/electron:Z \
    -v "$ROOT_DIR/.cache/electron-builder":/root/.cache/electron-builder:Z \
    -w /src \
    "$IMAGE" \
    bash -c "npm install && npm run dist"

cp "$APP_DIR"/dist/*.deb "$OUT_DIR/"
for f in "$APP_DIR"/dist/*.deb; do
  echo "  -> dist/$(basename "$f")"
done
