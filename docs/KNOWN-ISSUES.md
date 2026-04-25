# Joint Chiefs — Known Issues

**Last Updated:** 2026-04-25

A running list of known bugs, limitations, and rough edges. PRs that fix any of these are welcome.

## Design System Follow-ups (Setup App)

All six setup-app surfaces (`RootView`, `DisclosureView`, `KeysView`, `RolesWeightsView`, `InstallView`, `MCPConfigView`) are migrated to the Agentdeck tokens in `JointChiefsSetup/DesignSystem/`. Follow-up polish:

- **Ollama toggle** uses the system default `Toggle` chrome. Agentdeck doesn't yet spec a custom toggle style; revisit if the native look feels out of place against the warm surfaces.
- **Picker (Tiebreaker)** uses the native `.menu` picker; consensus/moderator moved to `AgentChip`. The menu picker still shows the macOS accent tint — acceptable for a dropdown, but worth revisiting if it reads as inconsistent.

### Sidebar update-status footer

Tracked as a set — the feature is functional in `UpdaterService.swift` + `RootView.swift` (currently uncommitted as WIP). Four polish items to address before or alongside the next release that lands the feature:

- **Pill kind is `.success` (green); should be `.info` or `.accent`.** Per `docs/DESIGN-SYSTEM.md`: *"Green means 'ready' — for success, merge-ready, validated states."* An "update available" notification is informational, not a validated state. Fix: in `RootView.swift` `UpdateStatusFooter`, change `kind: .success` → `kind: .info` (blue) or `kind: .accent` (warm-tan). One-line change.
- **Stale `availableUpdateVersion` after dismissed install modal.** If the user clicks the "update available" pill, Sparkle's install modal opens, and they dismiss it without installing, the pill stays visible until the next scheduled background check (Sparkle's default is hourly). Fix options: (a) wire a `SPUUserDriverDelegate` so dismissal clears the version, or (b) clear the version on the next `checkForUpdates()` call regardless of outcome and rely on Sparkle to re-fire `didFindValidUpdate` if still pending.
- **No "checking…" feedback during user-triggered check.** The button disables via `canCheckForUpdates` while Sparkle queries the appcast, but there's no spinner. On slow networks the click feels unresponsive. Fix: add a short-lived `isChecking` flag set in `UpdaterService.checkForUpdates()`, cleared when Sparkle's KVO fires `canCheckForUpdates = true` again. Render a `ProgressView` in the button label while set.
- **Pill / current-version typography scale mismatch.** `AgentPill` defaults to `agentSmall` (mono 12pt / 600); the current-version label below uses `agentXS` (11pt / 400). May feel chunky stacked. Fix: visual check after `scripts/build-app.sh` + reinstall; if mismatched, either expose a `compact` variant on `AgentPill` or override the pill's font locally in this footer.

## Active Bugs

_None currently tracked._

## Known Limitations

- **MCP SDK pinned pre-1.0.** `modelcontextprotocol/swift-sdk` is pinned to exact `0.12.0` in `Package.swift`. Review the SDK's release notes before bumping — the protocol and API surface may change across 0.x versions.
- **Dev-built keygetter uses ad-hoc code signature.** `swift build` produces an ad-hoc-signed `jointchiefs-keygetter`. That identity works for local Keychain access but is *not* the identity that end-user Keychain items are scoped to. Release builds must re-sign with `codesign --sign <Developer ID> --identifier com.jointchiefs.keygetter <path>` — the designated requirement derived from that signature is what `kc-keygetter-prototype` validated as stable across updates.
- **Keygetter discovery is best-effort.** `APIKeyResolver.locateKeygetter` checks `JOINTCHIEFS_KEYGETTER_PATH`, sibling-of-caller, and `/Applications/Joint Chiefs.app/Contents/Resources/`. If a user installs the app bundle elsewhere, they need to set the env var. Document in SECURITY.md before launch.
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
