#!/bin/bash
#
# make-dmg.sh — packs a built .app into a .dmg with an "Applications" shortcut,
# so users just open the disk image and drag the app onto Applications.
#
# Usage:  ./make-dmg.sh /path/to/INDDConverter.app dist/INDDConverter.dmg

set -euo pipefail

APP="${1:?Usage: make-dmg.sh <app> <output.dmg>}"
OUT="${2:?Usage: make-dmg.sh <app> <output.dmg>}"
VOLNAME="INDD IDML Converter"

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install shortcut

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGING"

echo "✓ DMG: $OUT"
