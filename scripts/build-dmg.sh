#!/bin/bash
# Creates a styled DMG with drag-to-Applications for Joint Chiefs.app.
#
# Run AFTER scripts/build-app.sh has produced build/Joint Chiefs.app.
# This script does NOT sign or notarize — that's a separate step that
# requires the user's Developer ID and Apple ID app-specific password.
#
# The output DMG (build/Joint Chiefs.dmg) is unsigned. Once Developer ID
# signing + notarization are wired up, the same layout is reused.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$REPO_ROOT/build/Joint Chiefs.app"
DMG_PATH="$REPO_ROOT/build/Joint-Chiefs.dmg"
VOLUME_NAME="Joint Chiefs"
ICON_PATH="$REPO_ROOT/Resources/AppIcon.icns"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: $APP_PATH not found." >&2
    echo "Run scripts/build-app.sh first." >&2
    exit 1
fi

if [[ ! -f "$ICON_PATH" ]]; then
    echo "warn: $ICON_PATH missing — DMG will use default volume icon" >&2
fi

# Remove old DMG if it exists (create-dmg refuses to overwrite).
rm -f "$DMG_PATH"

VOLICON_ARGS=()
if [[ -f "$ICON_PATH" ]]; then
    VOLICON_ARGS=(--volicon "$ICON_PATH")
fi

echo "==> Building DMG"

create-dmg \
    --volname "$VOLUME_NAME" \
    "${VOLICON_ARGS[@]}" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "Joint Chiefs.app" 150 185 \
    --app-drop-link 450 185 \
    --hide-extension "Joint Chiefs.app" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH"

echo ""
echo "==> DMG created"
echo "    $DMG_PATH"
echo "    $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "Next steps (require Developer ID + Apple ID):"
echo "  1. Sign the .app inside the DMG with Developer ID Application cert"
echo "  2. Notarize with: xcrun notarytool submit \"$DMG_PATH\" --wait"
echo "  3. Staple with:   xcrun stapler staple \"$DMG_PATH\""
echo "  4. Upload to jointchiefs.ai (private website repo)"
echo "  5. Update Homebrew cask formula with new version + SHA-256"
