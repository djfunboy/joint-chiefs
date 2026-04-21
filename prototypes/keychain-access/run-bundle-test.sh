#!/bin/bash
# Tests whether a helper inside a .app bundle can silently access Keychain items
# created by the bundle's main executable. If yes → Option B (keygetter-in-bundle) works.

set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="CA745866DC04909C26B8768F9969460231D36E97"
BUNDLE="TestApp.app"
BUILD_DIR="build"

echo "=== Bundle-helper Keychain prototype ==="
echo ""

# Reuse the existing kc-writer / kc-reader sources (legacy Keychain, no entitlement)
echo "--- Compiling into bundle ---"
swiftc -O kc-writer.swift -o "$BUNDLE/Contents/MacOS/TestApp"
swiftc -O kc-reader.swift -o "$BUNDLE/Contents/Resources/kc-keygetter"

# Also compile a standalone CLI-like binary that lives OUTSIDE the bundle
mkdir -p "$BUILD_DIR"
swiftc -O kc-reader.swift -o "$BUILD_DIR/external-cli"

echo "--- Signing bundle (single sign operation covers main exec + nested helper) ---"
codesign --force --deep --sign "$IDENTITY" "$BUNDLE"

echo "--- Signing external CLI (standalone) ---"
codesign --force --sign "$IDENTITY" "$BUILD_DIR/external-cli"

echo ""
echo "--- Checking designated requirements ---"
echo "Main exec DR:"
codesign -d -r - "$BUNDLE/Contents/MacOS/TestApp" 2>&1 | grep -A1 "designated"
echo "Helper DR:"
codesign -d -r - "$BUNDLE/Contents/Resources/kc-keygetter" 2>&1 | grep -A1 "designated"
echo "External CLI DR:"
codesign -d -r - "$BUILD_DIR/external-cli" 2>&1 | grep -A1 "designated"

echo ""
echo "=== Test 1: bundle main exec writes Keychain ==="
"$BUNDLE/Contents/MacOS/TestApp"

echo ""
echo "=== Test 2: helper INSIDE bundle reads Keychain ==="
"$BUNDLE/Contents/Resources/kc-keygetter" bundle-helper

echo ""
echo "=== Test 3: external CLI OUTSIDE bundle reads Keychain ==="
"$BUILD_DIR/external-cli" external-cli

echo ""
echo "=== Done ==="
echo "If Test 2 succeeded silently: Option B works — bundle helper shares Keychain access with main exec."
echo "If Test 3 also succeeded silently: same-identity sharing works even outside the bundle."
echo "If either triggered a dialog: Option B doesn't solve the problem cleanly."
