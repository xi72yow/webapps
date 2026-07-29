#!/usr/bin/env bash
# generates the app icons from tabler icons into icons/
#
#   ./scripts/make-icons.sh
#
# the results are committed, so a normal build needs neither network nor this
# script. re-run it after changing icon or color in apps.json.
#
# tabler icons are mit licensed, unlike the vendor logos they replace, so they
# can be shipped inside the packages instead of being downloaded on the target
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_DIR="$ROOT_DIR/icons"
APPS_JSON="$ROOT_DIR/apps.json"
TABLER_VERSION="3.46.0"
CDN="https://unpkg.com/@tabler/icons@${TABLER_VERSION}/icons/outline"

# the tile is 512x512, the glyph fills the inner 56% so it keeps clear of the
# rounded corners. 24 units of source viewbox scale by 512*0.56/24
GLYPH_SCALE="11.94"
GLYPH_OFFSET="112.6"

mkdir -p "$ICON_DIR"

fetch_glyph() {
  local icon="$1"
  local cache="$ROOT_DIR/.cache/tabler/${icon}.svg"

  if [ ! -f "$cache" ]; then
    mkdir -p "$(dirname "$cache")"
    curl -sfL "$CDN/${icon}.svg" -o "$cache"
  fi

  # keep the paths only, the wrapper svg brings its own attributes.
  # the first path is tabler's transparent 24x24 bounding box, which would
  # render as nothing but bloats every icon, so it goes
  grep -o '<path[^>]*/>' "$cache" | grep -v 'stroke="none"'
}

build_icon() {
  local name="$1" icon="$2" color="$3"
  local glyph

  glyph=$(fetch_glyph "$icon")

  cat > "$ICON_DIR/${name}.svg" << EOF
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="96" fill="${color}"/>
  <g transform="translate(${GLYPH_OFFSET} ${GLYPH_OFFSET}) scale(${GLYPH_SCALE})"
     fill="none" stroke="#ffffff" stroke-width="2"
     stroke-linecap="round" stroke-linejoin="round">
$(echo "$glyph" | sed 's/^/    /')
  </g>
</svg>
EOF

  echo "  -> icons/${name}.svg (${icon}, ${color})"
}

count=$(jq length "$APPS_JSON")
for i in $(seq 0 $((count - 1))); do
  build_icon \
    "$(jq -r ".[$i].name" "$APPS_JSON")" \
    "$(jq -r ".[$i].icon" "$APPS_JSON")" \
    "$(jq -r ".[$i].color" "$APPS_JSON")"
done

# the electron wrapper is packaged by electron-builder, which wants a png
build_icon "teams" "brand-teams" "#5059c9"
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 512 -h 512 "$ICON_DIR/teams.svg" -o "$ROOT_DIR/electron/build/icon.png"
else
  podman run --rm -v "$ROOT_DIR":/w:Z -w /w docker.io/library/debian:13-slim bash -c \
    "apt-get update -qq >/dev/null && apt-get install -y -qq librsvg2-bin >/dev/null 2>&1 \
     && rsvg-convert -w 512 -h 512 icons/teams.svg -o electron/build/icon.png"
fi
echo "  -> electron/build/icon.png"
