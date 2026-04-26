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

# Version metadata for Info.plist.
#
# CFBundleShortVersionString is the user-facing version (e.g. "0.5.2").
#
# CFBundleVersion is the build number Sparkle uses to decide whether one
# release is newer than another. It does **natural-numeric comparison** — not
# semver. Any release whose CFBundleVersion is lower than a previously-shipped
# release will trigger a downgrade in Sparkle's update dialog. This bit us in
# v0.5.0 (built with CFBundleVersion=5 while v0.4.0 used a Unix-timestamp build
# of 1776962397; Sparkle then offered v0.5.0 users a "downgrade" to v0.4.0).
# See tasks/lessons.md 2026-04-26.
#
# Permanent scheme (locked in starting v0.5.2):
#
#   - CFBundleVersion is a monotonically-increasing integer. Strictly greater
#     than every previously-shipped release. Never derived from a timestamp.
#   - v0.5.2 floor: 1777000000 (chosen to clear v0.4.0's legacy timestamp
#     1776962397 plus headroom). Increment by 1 per future release: v0.5.3 =
#     1777000001, v0.6.0 = 1777000002, etc.
#   - The release process MUST set JC_BUILD to the new monotonic int before
#     calling this script. Dev builds without JC_BUILD get a placeholder of 0
#     and a warning; that's harmless because dev builds aren't shipped.
#   - For release safety, the caller SHOULD also set JC_PREVIOUS_BUILD to the
#     previous release's build number; this script then refuses to build if
#     JC_BUILD is not strictly greater.
VERSION="${JC_VERSION:-0.0.0-dev}"
BUILD_NUMBER="${JC_BUILD:-0}"

if [[ "$BUILD_NUMBER" == "0" ]]; then
    echo "warn: building with placeholder CFBundleVersion=0 (dev mode)" >&2
    echo "      For release: set JC_BUILD to a monotonic int strictly greater" >&2
    echo "      than the previous release. See header of this script for the" >&2
    echo "      permanent scheme." >&2
elif [[ -n "${JC_PREVIOUS_BUILD:-}" ]]; then
    if (( BUILD_NUMBER <= JC_PREVIOUS_BUILD )); then
        echo "error: JC_BUILD ($BUILD_NUMBER) must be strictly greater than" >&2
        echo "       JC_PREVIOUS_BUILD ($JC_PREVIOUS_BUILD). Sparkle compares" >&2
        echo "       CFBundleVersion as a natural-numeric value; a non-monotonic" >&2
        echo "       build number will trigger a downgrade in the update dialog." >&2
        exit 1
    fi
fi

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
