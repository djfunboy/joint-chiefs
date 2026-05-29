# Joint Chiefs — Release Process

The signed-and-notarized macOS release flow, end to end.

> **Important:** `scripts/build-app.sh` only *assembles* the bundle — it does
> **not** codesign or notarize. Those steps are manual and are documented here.

## One-time setup — already done, do NOT redo

- **Developer ID certificate** — `Developer ID Application: Chris Doyle (VJMJQKCRMC)`
  in the login keychain. Confirm with `security find-identity -v -p codesigning`.
- **Notarization credential** — a `notarytool` keychain profile named
  **`JointChiefs`**, created once with `xcrun notarytool store-credentials`.
  It is stored in the keychain (account
  `com.apple.gke.notary.tool.saved-creds.JointChiefs`, synced via iCloud
  Keychain) and is reused by **every** release.
  - **Do not create a new app-specific password per release.** The profile is
    permanent. Every release just passes `--keychain-profile JointChiefs`.
  - If it is ever lost: generate one app-specific password at
    [account.apple.com](https://account.apple.com) → App-Specific Passwords,
    then `xcrun notarytool store-credentials JointChiefs --apple-id <id> --team-id VJMJQKCRMC`.
- **Sparkle EdDSA key** — the private key that signs appcast updates. Local-only,
  gitignored. Never committed.

## Release steps

### 1. Version
Pick `vX.Y.Z` and a `CFBundleVersion` that is a monotonic integer **strictly
greater** than the last shipped release (currently v0.5.10 = `1777000008`; increment by 1). Bump it
in `CLAUDE.md` (Latest release line), `Casks/joint-chiefs.rb` (`version`),
`docs/BUILD-PLAN.md` (release log), and any other version-tagged docs.

### 2. Test
```
cd JointChiefs && swift test
```
Zero failures, or stop.

### 3. Assemble the app bundle
```
JC_VERSION=X.Y.Z JC_BUILD=<n> JC_PREVIOUS_BUILD=<prev> bash scripts/build-app.sh
```
Produces `build/Joint Chiefs.app` — **unsigned**.

### 4. Codesign (manual)
The repo lives in Dropbox, which re-adds `com.apple.FinderInfo` xattrs that
break `codesign`. **Stage the bundle to `/tmp` first** (outside Dropbox sync):
```
STAGE=/tmp/jc-release
rm -rf "$STAGE" && mkdir -p "$STAGE"
cp -R "build/Joint Chiefs.app" "$STAGE/Joint Chiefs.app"
xattr -cr "$STAGE/Joint Chiefs.app"

APP="$STAGE/Joint Chiefs.app"
# Sign by certificate SHA-1 hash, NOT by name. Two "Developer ID Application:
# Chris Doyle (VJMJQKCRMC)" certs live in the login keychain (renewal overlap),
# so `--sign "Developer ID Application: ..."` fails with "ambiguous" and silently
# leaves the bundle ad-hoc/linker-signed — notarization then returns Invalid
# ("no usable signature"). Confirm the hash with `security find-identity -v -p codesigning`.
ID="E2EF8DBDD708A1857D5688F424272BE6821E463E"

# Sign inside-out: nested executables, then the framework, then the bundle.
codesign --force --options runtime --timestamp --sign "$ID" \
  --identifier com.jointchiefs.keygetter "$APP/Contents/Resources/jointchiefs-keygetter"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Resources/jointchiefs"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Resources/jointchiefs-mcp"
codesign --force --options runtime --timestamp --deep --sign "$ID" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "$ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```
The keygetter **must** carry `--identifier com.jointchiefs.keygetter` — the
Keychain ACL design depends on its stable Designated Requirement surviving
rebuilds. `--options runtime` (hardened runtime) is required for notarization.

### 5. Build and sign the DMG
```
cd "$STAGE"
create-dmg --volname "Joint Chiefs" \
  --volicon "<repo-root>/Resources/AppIcon.icns" \
  --window-pos 200 120 --window-size 600 400 --icon-size 128 \
  --icon "Joint Chiefs.app" 150 185 --app-drop-link 450 185 \
  --hide-extension "Joint Chiefs.app" --no-internet-enable \
  "Joint-Chiefs.dmg" "Joint Chiefs.app"
codesign --force --timestamp --sign "$ID" "Joint-Chiefs.dmg"
```

### 6. Notarize and staple
```
xcrun notarytool submit "Joint-Chiefs.dmg" --keychain-profile "JointChiefs" --wait
xcrun stapler staple "Joint-Chiefs.dmg"
spctl -a -t open --context context:primary-signature -vv "Joint-Chiefs.dmg"
```
The `spctl` check must report `accepted` / `source=Notarized Developer ID`.
Notarization typically completes in 2–5 minutes.

### 7. Cold-machine smoke test
```
rm -rf "/Applications/Joint Chiefs.app"
```
Mount the DMG, drag-install, launch, confirm the first-run window appears and
the process stays alive. Signing + notarization do **not** catch dyld/rpath
failures — this step does (see `tasks/lessons.md`, the v0.3.1 hotfix).

### 8. Hash and cask
```
shasum -a 256 Joint-Chiefs.dmg
```
Paste the hash into `Casks/joint-chiefs.rb` `sha256`, and bump `version`.

### 9. Sparkle appcast
EdDSA-sign the DMG with Sparkle's `sign_update` tool and the local private key,
then add a new `<item>` to `distribution/appcast.xml`. `sparkle:version` must
equal the new `CFBundleVersion` (the integer), **not** the short version string.

### 10. Publish
1. Commit (`release: vX.Y.Z — <summary>`), tag `vX.Y.Z`, push to `main`.
2. `gh release create vX.Y.Z` with `Joint-Chiefs.dmg` attached.
3. Website repo (`joint-chiefs-website`, private): update the download page,
   JSON-LD `softwareVersion`, the guide announce bars, and `appcast.xml`. Push —
   Netlify auto-deploys.

Run the full five-part pre-release review from `CLAUDE.md` before tagging.
