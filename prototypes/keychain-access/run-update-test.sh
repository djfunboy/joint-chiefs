#!/bin/bash
# Simulates an app update. Tests whether a rebuilt keygetter (different cdhash,
# same signing identifier) can still read Keychain items the pre-update keygetter wrote.
#
# If silent → identifier-based DR survives updates, we're production-ready.
# If dialog → every app update breaks Keychain silence; need a different architecture.

set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="CA745866DC04909C26B8768F9969460231D36E97"
BUNDLE="TestApp.app"
IDENT="com.jointchiefs.keygetter"

echo "=== Update-survives-rebuild test ==="
echo ""

mkdir -p "$BUNDLE/Contents/Resources"

# --- v1: write an item with the "old" keygetter ---
echo "--- Building v1 keygetter ---"
swiftc -O kc-keygetter.swift -o "$BUNDLE/Contents/Resources/jointchiefs-keygetter"
codesign --force --sign "$IDENTITY" --identifier "$IDENT" "$BUNDLE/Contents/Resources/jointchiefs-keygetter"

echo "v1 DR:"
codesign -d -r - "$BUNDLE/Contents/Resources/jointchiefs-keygetter" 2>&1 | grep "designated" | head -1
V1_CDHASH=$(codesign -d -vvvv "$BUNDLE/Contents/Resources/jointchiefs-keygetter" 2>&1 | grep -i "cdhash=" | head -1)
echo "v1 $V1_CDHASH"

echo ""
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" delete openai || true
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" write openai "sk-v1-marker-abc123"
echo "v1 wrote the item."

echo ""
# --- v2: simulate an update. Modify the source to force different bytes, rebuild, same identifier ---
echo "--- Simulating app update: rebuilding keygetter (different bytes, SAME identifier) ---"
TMP_DIR=$(mktemp -d)
TMP_SRC="$TMP_DIR/kc-keygetter-v2.swift"
cp kc-keygetter.swift "$TMP_SRC"
# Inject a used stderr print with a unique marker so swiftc keeps it and bytes differ.
# Preserves all Keychain lookup semantics (same service, same account path).
MARKER="v2-build-$(date +%s)"
sed -i '' "1i\\
FileHandle.standardError.write(Data(\"[keygetter-marker] ${MARKER}\\\\n\".utf8));
" "$TMP_SRC"
swiftc -O "$TMP_SRC" -o "$BUNDLE/Contents/Resources/jointchiefs-keygetter"
rm -rf "$TMP_DIR"
codesign --force --sign "$IDENTITY" --identifier "$IDENT" "$BUNDLE/Contents/Resources/jointchiefs-keygetter"

echo "v2 DR:"
codesign -d -r - "$BUNDLE/Contents/Resources/jointchiefs-keygetter" 2>&1 | grep "designated" | head -1
V2_CDHASH=$(codesign -d -vvvv "$BUNDLE/Contents/Resources/jointchiefs-keygetter" 2>&1 | grep -i "cdhash=" | head -1)
echo "v2 $V2_CDHASH"

if [[ "$V1_CDHASH" == "$V2_CDHASH" ]]; then
    echo "WARNING: v1 and v2 have identical cdhashes — binary bytes weren't different enough. Test inconclusive."
    exit 2
fi

echo ""
echo "=== v2 reads the item v1 wrote ==="
"$BUNDLE/Contents/Resources/jointchiefs-keygetter" read openai > /tmp/kc-update-test
echo "v2 read back: $(cat /tmp/kc-update-test | cut -c1-12)…"

rm -f /tmp/kc-update-test

echo ""
echo "=== Done ==="
echo ""
echo "If the read succeeded silently → identifier-based DR survives updates."
echo "If a dialog fired → we need either matching cdhash (Apple guarantees via notarization?) or a different architecture."
