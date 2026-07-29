#!/usr/bin/env bash
# builds one .deb per entry in apps.json, each a chrome --app launcher
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/dist"
WORK_DIR="$ROOT_DIR/.build/chrome"
APPS_JSON="$ROOT_DIR/apps.json"

# amd hw video decode/encode, multi-plane off avoids the white-frame bug on rdna3
CHROME_FLAGS="--enable-features=VaapiVideoDecoder,VaapiVideoEncoder,AcceleratedVideoEncoder --disable-features=UseMultiPlaneFormatForHardwareVideo"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required. Install with: sudo apt install jq" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

build_app() {
  local index="$1"
  local name display_name url categories version
  local domain path wm_class pkg_dir

  name=$(jq -r ".[$index].name" "$APPS_JSON")
  display_name=$(jq -r ".[$index].display_name" "$APPS_JSON")
  url=$(jq -r ".[$index].url" "$APPS_JSON")
  categories=$(jq -r ".[$index].categories" "$APPS_JSON")
  version=$(jq -r ".[$index].version" "$APPS_JSON")
  # ci appends the run number so every release outranks the previous one
  # without anyone editing apps.json. '+' keeps dpkg ordering intact
  [ -n "${BUILD_NUMBER:-}" ] && version="${version}+${BUILD_NUMBER}"

  # chrome derives WM_CLASS as chrome-{domain}__{path}-Default, slashes become underscores
  domain=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
  path=$(echo "$url" | sed -E 's|https?://[^/]+/?||; s|/$||; s|/|_|g')
  wm_class="chrome-${domain}__${path}-Default"
  pkg_dir="$WORK_DIR/$name"

  echo "Building $display_name ($version)..."

  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir/DEBIAN" "$pkg_dir/usr/share/applications" \
           "$pkg_dir/usr/share/icons/hicolor/scalable/apps" \
           "$pkg_dir/usr/share/doc/${name}-desktop"

  cp "$ROOT_DIR/icons/${name}.svg" \
     "$pkg_dir/usr/share/icons/hicolor/scalable/apps/${name}.svg"
  # the icons are derived from tabler icons, whose mit license asks for the
  # notice to travel with them
  cp "$ROOT_DIR/icons/LICENSE.tabler" \
     "$pkg_dir/usr/share/doc/${name}-desktop/copyright"

  cat > "$pkg_dir/DEBIAN/control" << EOF
Package: ${name}-desktop
Version: ${version}
Section: web
Priority: optional
Architecture: all
Depends: google-chrome-stable
Maintainer: xi72yow <xi72yow@github.com>
Description: ${display_name} Desktop App
 Launches ${display_name} as a standalone Chrome App window.
EOF

  # up to 1.1.0 the postinst downloaded the vendor logo into /usr/share. that
  # copy is not tracked by dpkg, so it would linger and shadow the shipped icon
  cat > "$pkg_dir/DEBIAN/postinst" << EOF
#!/bin/bash
set -e

rm -f "/usr/share/icons/hicolor/256x256/apps/${name}.png"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true
fi
EOF

  cat > "$pkg_dir/DEBIAN/postrm" << EOF
#!/bin/bash
set -e

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true
fi
EOF

  chmod 755 "$pkg_dir/DEBIAN/postinst" "$pkg_dir/DEBIAN/postrm"

  cat > "$pkg_dir/usr/share/applications/${name}.desktop" << EOF
[Desktop Entry]
Name=${display_name}
Comment=${display_name}
Exec=/opt/google/chrome/chrome ${CHROME_FLAGS} --app=${url}
Icon=${name}
Type=Application
Categories=${categories}
StartupWMClass=${wm_class}
EOF

  dpkg-deb --root-owner-group --build "$pkg_dir" "$OUT_DIR/${name}-desktop_${version}_all.deb" >/dev/null
  echo "  -> dist/${name}-desktop_${version}_all.deb"
}

APP_NAME="${1:-}"
app_count=$(jq length "$APPS_JSON")

if [ -n "$APP_NAME" ]; then
  for i in $(seq 0 $((app_count - 1))); do
    if [ "$(jq -r ".[$i].name" "$APPS_JSON")" = "$APP_NAME" ]; then
      build_app "$i"
      exit 0
    fi
  done
  echo "Unknown app: $APP_NAME" >&2
  echo "Available: $(jq -r '.[].name' "$APPS_JSON" | tr '\n' ' ')" >&2
  exit 1
fi

for i in $(seq 0 $((app_count - 1))); do
  build_app "$i"
done
