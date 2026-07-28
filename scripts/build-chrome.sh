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
  local name display_name url icon_url icon_ext categories version
  local domain path wm_class icon_dir icon_path pkg_dir

  name=$(jq -r ".[$index].name" "$APPS_JSON")
  display_name=$(jq -r ".[$index].display_name" "$APPS_JSON")
  url=$(jq -r ".[$index].url" "$APPS_JSON")
  icon_url=$(jq -r ".[$index].icon_url" "$APPS_JSON")
  icon_ext=$(jq -r ".[$index].icon_ext" "$APPS_JSON")
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

  if [ "$icon_ext" = "svg" ]; then
    icon_dir="/usr/share/icons/hicolor/scalable/apps"
    icon_path="${icon_dir}/${name}.svg"
  else
    icon_dir="/usr/share/icons/hicolor/256x256/apps"
    icon_path="${icon_dir}/${name}.png"
  fi

  echo "Building $display_name ($version)..."

  rm -rf "$pkg_dir"
  mkdir -p "$pkg_dir/DEBIAN" "$pkg_dir/usr/share/applications"

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
 The icon is downloaded during installation.
EOF

  # the app logos are third-party trademarks, so they are fetched at install
  # time instead of being stored in this repo
  cat > "$pkg_dir/DEBIAN/postinst" << EOF
#!/bin/bash
set -e

mkdir -p "$icon_dir"

if command -v curl >/dev/null 2>&1; then
    curl -sfL "$icon_url" -o "$icon_path" || true
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$icon_path" "$icon_url" || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true
fi
EOF

  cat > "$pkg_dir/DEBIAN/postrm" << EOF
#!/bin/bash
set -e

if [ "\$1" = "remove" ] || [ "\$1" = "purge" ]; then
    rm -f "$icon_path"
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true
    fi
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
