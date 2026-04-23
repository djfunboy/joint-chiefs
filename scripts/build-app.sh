#!/bin/bash
# Assemble Joint Chiefs.app from the SPM release build.
#
# Output: build/Joint Chiefs.app
#
#   Contents/
#     Info.plist
#     MacOS/
#       jointchiefs-setup          (the setup app — bundle's main executable)
#     Resources/
#       jointchiefs                (CLI)
#       jointchiefs-mcp            (MCP stdio server)
#       jointchiefs-keygetter      (Keychain-access binary — APIKeyResolver.locateKeygetter finds it here)
#
# No signing or notarization — those live in Phase 10. This script is intentionally
# deterministic so CI can re-run it with the same inputs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG_ROOT="$REPO_ROOT/JointChiefs"
BUILD_DIR="$REPO_ROOT/build"
APP_PATH="$BUILD_DIR/Joint Chiefs.app"
INFO_PLIST_TEMPLATE="$REPO_ROOT/scripts/Info.plist"

# Version metadata for Info.plist. CFBundleShortVersionString is the user-facing
# version; CFBundleVersion is a monotonic build number (epoch seconds is fine
# for dev builds, CI will overwrite both via env).
VERSION="${JC_VERSION:-0.1.0}"
BUILD_NUMBER="${JC_BUILD:-$(date +%s)}"

echo "==> Building SPM targets (release)"
cd "$PKG_ROOT"
swift build -c release

BIN_DIR="$PKG_ROOT/.build/release"
REQUIRED_BINARIES=(jointchiefs jointchiefs-mcp jointchiefs-keygetter jointchiefs-setup)
for name in "${REQUIRED_BINARIES[@]}"; do
    if [[ ! -x "$BIN_DIR/$name" ]]; then
        echo "error: expected binary not found at $BIN_DIR/$name" >&2
        exit 1
    fi
done

echo "==> Clearing previous bundle"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

echo "==> Writing Info.plist (version=$VERSION build=$BUILD_NUMBER)"
sed \
    -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$INFO_PLIST_TEMPLATE" > "$APP_PATH/Contents/Info.plist"

echo "==> Copying main executable into Contents/MacOS"
cp "$BIN_DIR/jointchiefs-setup" "$APP_PATH/Contents/MacOS/jointchiefs-setup"
chmod 0755 "$APP_PATH/Contents/MacOS/jointchiefs-setup"

echo "==> Copying CLI binaries into Contents/Resources"
for name in jointchiefs jointchiefs-mcp jointchiefs-keygetter; do
    cp "$BIN_DIR/$name" "$APP_PATH/Contents/Resources/$name"
    chmod 0755 "$APP_PATH/Contents/Resources/$name"
done

# Sparkle.framework ships as a binary XCFramework via SPM. The .framework on
# disk after `swift build` already contains XPCServices, the Autoupdate helper,
# and the Updater.app helper — we just need to mirror it into Contents/Frameworks/.
# Copy with -R to preserve symlinks (Versions/Current -> B).
SPARKLE_SRC="$BIN_DIR/Sparkle.framework"
if [[ -d "$SPARKLE_SRC" ]]; then
    echo "==> Copying Sparkle.framework into Contents/Frameworks"
    mkdir -p "$APP_PATH/Contents/Frameworks"
    rm -rf "$APP_PATH/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE_SRC" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
else
    echo "error: Sparkle.framework not found at $SPARKLE_SRC" >&2
    exit 1
fi

# Sparkle's install name is @rpath/Sparkle.framework/..., and SPM doesn't add an
# rpath entry pointing at the bundle's Contents/Frameworks/. Without this, the
# app launches, dyld fails to find Sparkle, and macOS silently falls back to
# any other Joint Chiefs.app it can find (e.g. an older /Applications copy).
# Patch the main executable's rpath so the framework loads from the bundle.
echo "==> Patching Sparkle rpath on main executable"
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP_PATH/Contents/MacOS/jointchiefs-setup"

ICON_SRC="$REPO_ROOT/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    echo "==> Copying AppIcon.icns into Contents/Resources"
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
else
    echo "warn: $ICON_SRC missing — run scripts/generate-icon.sh before building for release" >&2
fi

echo "==> Done: $APP_PATH"
echo "    open \"$APP_PATH\"   # launch"
echo "    ls -la \"$APP_PATH/Contents\""
