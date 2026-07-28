#!/bin/bash
# the teams logo is a microsoft trademark, so it is fetched at install time
# instead of being shipped in this repo (same pattern as betas/chrome-apps)
set -e

ICON_URL="https://statics.teams.cdn.office.net/hashed/favicon/prod/favicon-192x192-442a326.png"

for size in 256x256 512x512; do
    # keine ${}-syntax, electron-builder ersetzt das als makro
    target="/usr/share/icons/hicolor/$size/apps/teams.png"
    [ -f "$target" ] || continue
    if command -v curl >/dev/null 2>&1; then
        curl -sfL "$ICON_URL" -o "$target" || true
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$target" "$ICON_URL" || true
    fi
done

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true
fi
