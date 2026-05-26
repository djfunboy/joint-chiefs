# Joint Chiefs — Known Issues

**Last Updated:** 2026-05-17

A running list of known bugs, limitations, and rough edges. PRs that fix any of these are welcome.

## Design System Follow-ups (Setup App)

All six setup-app view files (`RootView`, `UsageView`, `KeysView`, `RolesWeightsView`, `MCPConfigView`, `DisclosureView` — the last renders as "Privacy") are migrated to the Agentdeck tokens in `JointChiefsSetup/DesignSystem/`. Follow-up polish:

- **Ollama / OpenAI-compatible enable toggles** use the system default `Toggle` chrome. Agentdeck doesn't yet spec a custom toggle style; revisit if the native look feels out of place against the warm surfaces.
- **Picker (Tiebreaker)** uses the native `.menu` picker; consensus/moderator moved to `AgentChip`. The menu picker still shows the macOS accent tint — acceptable for a dropdown, but worth revisiting if it reads as inconsistent.

## Active Bugs

- **No pre-flight validation when picking a moderator without a saved API key.** `RolesWeightsView` lets the user select any provider as moderator regardless of whether that provider's key is saved. Save accepts it and the review blows up at runtime. Fix: inline error in `RolesWeightsView.moderatorSection` when `model.keyStatuses[selection]` is `.unconfigured`/`.none`/`.failed`, or disable Save until resolved. Originally flagged in the 04-23 UX review; verified still open against `RolesWeightsView.swift` on 2026-04-26.

## Known Limitations

- **MCP SDK pinned pre-1.0.** `modelcontextprotocol/swift-sdk` is pinned to exact `0.12.0` in `Package.swift`. Review the SDK's release notes before bumping — the protocol and API surface may change across 0.x versions.
- **Keygetter discovery is best-effort.** `APIKeyResolver.locateKeygetter` checks `JOINTCHIEFS_KEYGETTER_PATH`, sibling-of-caller, and `/Applications/Joint Chiefs.app/Contents/Resources/`. If a user installs the app bundle elsewhere, they need to set the env var. Document in SECURITY.md before launch.
- **Legacy-Keychain migration isn't end-to-end tested.** `CredentialStore` (the live file store) is covered by unit tests, and the setup app's Save verifies its own write round-trip. But the `keygetter migrate` path reads v0.5.6-era items out of the macOS Keychain — `LegacyKeychainStore.retrieve` can't be sandboxed in a unit test (it needs a real Keychain item and may surface an access prompt). Migration is tracked as manual QA: install v0.5.7 on a machine with v0.5.6 Keychain keys and confirm they land in `credentials.json` with the Keychain items removed.
- **Convergence detection is title-similarity based.** The adaptive early-break heuristic compares finding titles across rounds. It may stop debate too early when models phrase the same finding differently, or too late when they word the same surface issue identically but disagree on substance.

## Roadmap-Adjacent

These were raised by Joint Chiefs reviewing its own source and remain open:

- Provider attribution can be lost in the non-streaming error path.
- Logger subsystem is hardcoded, which limits reuse if `JointChiefsCore` is embedded in another app.

## QA Areas Needing More Coverage

Manual verification gaps (automated tests cover the unit and orchestrator layers, but these need real-world runs):

- [ ] Adaptive early-break behavior with all 6 providers under load.
- [ ] Hub-and-spoke moderator synthesis quality on large diffs (>1000 lines).
- [ ] Headless credential read: `credentials.json` resolves with no logged-in GUI user (SSH / cron / `launchctl asuser`) — the property the v0.5.7 file store exists for.
- [ ] Legacy-Keychain migration on a real v0.5.6→v0.5.7 upgrade: keys move into `credentials.json`, Keychain items removed, no data loss.
- [ ] CLI behavior when no API keys are configured (should print a clear error).
- [ ] CLI behavior when only one provider is configured (should still produce useful output).
- [ ] VoiceOver nav across the five setup-app views with a live screen reader (tokens + `.isHeader` traits + pill labels + slider labels added; needs smoke test).
