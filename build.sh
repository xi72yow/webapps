#!/usr/bin/env bash
# builds every package in this repo into dist/
#
#   ./build.sh              everything
#   ./build.sh chrome       only the chrome app launchers
#   ./build.sh chrome outlook   only one of them
#   ./build.sh electron     only the electron teams wrapper
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-all}"

case "$TARGET" in
  chrome)
    bash "$ROOT_DIR/scripts/build-chrome.sh" "${2:-}"
    ;;
  electron)
    bash "$ROOT_DIR/scripts/build-electron.sh"
    ;;
  all)
    bash "$ROOT_DIR/scripts/build-chrome.sh"
    bash "$ROOT_DIR/scripts/build-electron.sh"
    ;;
  *)
    echo "Usage: $0 [all|chrome [app]|electron]" >&2
    exit 1
    ;;
esac

echo
echo "Packages in dist/:"
ls -1 "$ROOT_DIR"/dist/*.deb
echo
echo "Install with: sudo apt install $ROOT_DIR/dist/<package>.deb"
