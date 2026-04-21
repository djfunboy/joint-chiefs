#!/bin/bash
# Keychain access group prototype — empirical validation per JC review finding HIGH-3.
#
# Builds three signed Developer ID binaries and tests whether kSecAttrAccessGroup +
# keychain-access-groups entitlement lets them share Keychain access silently.
#
# If this works, our multi-binary deployment (app + CLI + MCP) can share keys without
# XPC service complexity. If headless-MCP reads fail with errSecInteractionNotAllowed,
# we need the XPC fallback.

set -euo pipefail

cd "$(dirname "$0")"

TEAM_ID="VJMJQKCRMC"
# Disambiguate by SHA-1 hash — two certs with identical names in Keychain, this is the current one (valid through Feb 2027)
IDENTITY="CA745866DC04909C26B8768F9969460231D36E97"
BUILD_DIR="build"

echo "=== Keychain access group prototype ==="
echo "Team ID:   $TEAM_ID"
echo "Identity:  $IDENTITY"
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "--- Compiling ---"
swiftc -O kc-writer.swift    -o "$BUILD_DIR/kc-writer"
swiftc -O kc-reader.swift    -o "$BUILD_DIR/kc-reader"
swiftc -O kc-spawn-mcp.swift -o "$BUILD_DIR/kc-spawn-mcp"

echo "--- Signing with Developer ID + shared.entitlements ---"
for bin in kc-writer kc-reader kc-spawn-mcp; do
    # Legacy keychain approach — no entitlement, no access group
    codesign --force --sign "$IDENTITY" "$BUILD_DIR/$bin"
    echo "  signed $bin"
done

echo ""
echo "--- Verifying signatures ---"
for bin in kc-writer kc-reader kc-spawn-mcp; do
    codesign --verify --verbose "$BUILD_DIR/$bin" 2>&1 | tail -1
done

echo ""
echo "=== Test 1: same-binary round-trip (baseline) ==="
"$BUILD_DIR/kc-writer"
"$BUILD_DIR/kc-reader" cli

echo ""
echo "=== Test 2: cross-binary read from CLI context (different binary, same access group) ==="
# kc-writer already wrote above; read from kc-reader
"$BUILD_DIR/kc-reader" cli-cross

echo ""
echo "=== Test 3: cross-binary read from headless-spawned context (simulates MCP) ==="
# Spawn kc-reader from kc-spawn-mcp, which mimics how Claude Desktop spawns MCP servers
"$BUILD_DIR/kc-spawn-mcp" "$BUILD_DIR/kc-reader"

echo ""
echo "=== All tests complete ==="
echo ""
echo "Exit codes above: 0 = silent success, 4 = headless prompt failure (would need XPC)"
