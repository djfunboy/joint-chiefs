# Joint Chiefs — Known Issues

**Last Updated:** 2026-04-21

A running list of known bugs, limitations, and rough edges. PRs that fix any of these are welcome.

## Design System Follow-ups (Setup App)

All six setup-app surfaces (`RootView`, `DisclosureView`, `KeysView`, `RolesWeightsView`, `InstallView`, `MCPConfigView`) are migrated to the Agentdeck tokens in `JointChiefsSetup/DesignSystem/`. Follow-up polish:

- **Ollama toggle** uses the system default `Toggle` chrome. Agentdeck doesn't yet spec a custom toggle style; revisit if the native look feels out of place against the warm surfaces.
- **Picker (Tiebreaker)** uses the native `.menu` picker; consensus/moderator moved to `AgentChip`. The menu picker still shows the macOS accent tint — acceptable for a dropdown, but worth revisiting if it reads as inconsistent.

## Active Bugs

_None currently tracked._

## Known Limitations

- **MCP SDK pinned pre-1.0.** `modelcontextprotocol/swift-sdk` is pinned to exact `0.12.0` in `Package.swift`. Review the SDK's release notes before bumping — the protocol and API surface may change across 0.x versions.
- **Dev-built keygetter uses ad-hoc code signature.** `swift build` produces an ad-hoc-signed `jointchiefs-keygetter`. That identity works for local Keychain access but is *not* the identity that end-user Keychain items are scoped to. Release builds must re-sign with `codesign --sign <Developer ID> --identifier com.jointchiefs.keygetter <path>` — the designated requirement derived from that signature is what `kc-keygetter-prototype` validated as stable across updates.
- **Keygetter discovery is best-effort.** `APIKeyResolver.locateKeygetter` checks `JOINTCHIEFS_KEYGETTER_PATH`, sibling-of-caller, and `/Applications/Joint Chiefs.app/Contents/Resources/`. If a user installs the app bundle elsewhere, they need to set the env var. Document in SECURITY.md before launch.
- **Setup app bundle has no app icon yet.** `scripts/build-app.sh` produces `build/Joint Chiefs.app` with a valid Info.plist, correct Contents/MacOS + Contents/Resources layout, and LaunchServices-compatible metadata. It launches and stays foregrounded via `NSApp.setActivationPolicy(.regular)`. Missing: `Resources/AppIcon.icns` plus the matching `CFBundleIconFile` key in Info.plist. Not blocking usage; visible as a generic Finder icon until addressed. Tracked in Phase 10.
- **Setup app's key-write path isn't end-to-end tested.** `APIKeyResolver.writeViaKeygetter` / `deleteViaKeygetter` were added for the setup app and shell out to the keygetter's `write` / `delete` subcommands (both already covered by the keygetter's exit-code contract). A full round-trip "write from setup app → read from CLI" test requires Keychain access a unit test can't sandbox — tracked as manual QA.
- **Convergence detection is title-similarity based.** The adaptive early-break heuristic compares finding titles across rounds. It may stop debate too early when models phrase the same finding differently, or too late when they word the same surface issue identically but disagree on substance.

## Roadmap-Adjacent

These were raised by Joint Chiefs reviewing its own source and remain open:

- Provider attribution can be lost in the non-streaming error path.
- Logger subsystem is hardcoded, which limits reuse if `JointChiefsCore` is embedded in another app.
- `ReviewProvider` existential is passed across `TaskGroup` boundaries without explicit `Sendable` annotation.

## QA Areas Needing More Coverage

Manual verification gaps (automated tests cover the unit and orchestrator layers, but these need real-world runs):

- [ ] Adaptive early-break behavior with all 5 providers under load.
- [ ] Hub-and-spoke moderator synthesis quality on large diffs (>1000 lines).
- [ ] Keychain storage with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` across reboots.
- [ ] CLI behavior when no API keys are configured (should print a clear error).
- [ ] CLI behavior when only one provider is configured (should still produce useful output).
- [ ] VoiceOver nav across the five setup-app views with a live screen reader (tokens + `.isHeader` traits + pill labels + slider labels added; needs smoke test).
