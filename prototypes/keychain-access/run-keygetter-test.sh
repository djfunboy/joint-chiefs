#!/bin/bash
# Tests Option B: single keygetter binary inside the app bundle as the sole
# Keychain agent. CLI/MCP invoke it via Process to read keys.
#
# Key insight: only ONE binary ever touches the Keychain. ACL trusts only that
# binary's identity. No cross-binary sharing problem because no cross-binary access.

set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="CA745866DC04909C26B8768F9969460231D36E97"
BUNDLE="TestApp.app"
BUILD_DIR="build"

echo "=== Single-keygetter Keychain prototype (Option B) ==="
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "--- Compiling ---"
swiftc -O kc-keygetter.swift  -o "$BUNDLE/Contents/Resources/jointchiefs-keygetter"
swiftc -O kc-cli-caller.swift -o "$BUILD_DIR/cli-caller"
swiftc -O kc-spawn-mcp.swift  -o "$BUILD_DIR/mcp-spawner"

# Tiny stub for the bundle main exec (required by macOS, never invoked in these tests)
cat > "$BUNDLE/Contents/MacOS/TestApp.swift" <<'EOF'
import Foundation
print("stub")
EOF
swiftc -O "$BUNDLE/Contents/MacOS/TestApp.swift" -o "$BUNDLE/Contents/MacOS/TestApp"
rm "$BUNDLE/Contents/MacOS/TestApp.swift"

echo "--- Signing bundle (deep signs nested keygetter) ---"
codesign --force --deep --sign "$IDENTITY" "$BUNDLE"

echo "--- Signing external binaries (same Developer ID, different identifiers) ---"
codesign --force --sign "$IDENTITY" "$BUILD_DIR/cli-caller"
codesign --force --sign "$IDENTITY" "$BUILD_DIR/mcp-spawner"

echo ""
echo "--- Keygetter DR ---"
codesign -d -r - "$BUNDLE/Contents/Resources/jointchiefs-keygetter" 2>&1 | grep "designated"

echo ""
echo "=== Cleanup: delete any prior test key ==="
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" delete openai || true

echo ""
echo "=== Test 1: keygetter writes (simulating the app's key-save flow) ==="
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" write openai "sk-keygetter-test-xyz789"

echo ""
echo "=== Test 2: keygetter reads from its own process (baseline — should always work) ==="
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" read openai > /tmp/kc-test-readback
echo "[test2] read back: $(cat /tmp/kc-test-readback | cut -c1-8)…"

echo ""
echo "=== Test 3: CLI-like binary (outside bundle) invokes keygetter to read ==="
"$BUILD_DIR/cli-caller" "$BUNDLE/Contents/Resources/jointchiefs-keygetter" openai

echo ""
echo "=== Test 4: headless-spawned caller invokes keygetter (simulates MCP via Claude Desktop) ==="
# Use the existing spawn-mcp binary with a small wrapper that invokes the keygetter directly
cat > /tmp/headless-invoke.sh <<EOF
#!/bin/bash
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" read openai
EOF
chmod +x /tmp/headless-invoke.sh
"$BUILD_DIR/mcp-spawner" /tmp/headless-invoke.sh

echo ""
echo "=== Done ==="
echo ""
echo "Interpretation:"
echo "  Test 2 success (silent) = expected, keygetter reads its own items"
echo "  Test 3 success (silent) = Option B works for CLI invocation"
echo "  Test 4 success (silent) = Option B works even in headless context"
echo "  Any test blocked by a dialog you had to approve = Option B still requires user interaction"

rm -f /tmp/headless-invoke.sh /tmp/kc-test-readback
