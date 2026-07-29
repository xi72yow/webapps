#!/bin/bash
# the icon ships inside the package, see scripts/make-icons.sh. it used to be
# downloaded here, which silently failed whenever packagekit applied the update
# offline during boot, leaving the placeholder in place
set -e

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ || true
fi
