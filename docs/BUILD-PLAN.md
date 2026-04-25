# Joint Chiefs — Build Plan

**Version:** 1.5
**Last Updated:** 2026-04-25

## What's Built

Joint Chiefs has matured from "solo-use CLI" into a three-surface product in
progress: CLI, stdio MCP server, and (still to come) a setup app.

- **CLI** (`jointchiefs`) — streaming multi-model review, same UX as v1
- **MCP server** (`jointchiefs-mcp`) — stdio-only; initialize + tools/list smoke-tested
- **Keygetter** (`jointchiefs-keygetter`) — single signed binary authoritative over Keychain access
- **`APIKeyResolver`** — env var first (CI fallback), then keygetter; CLI and MCP both funnel through it
- **`StrategyConfig` + `StrategyConfigStore`** — moderator, consensus mode, tiebreaker, rounds, timeouts, rate limits, persisted to `~/Library/Application Support/Joint Chiefs/strategy.json`
- **5 providers live:** OpenAI, Gemini, Grok, Anthropic Claude, Ollama — all SSE-streamed
- **Hub-and-spoke debate:** OpenAI / Gemini / Grok are spokes, Claude is moderator/decider; adaptive early break on convergence
- **Anonymous synthesis:** model identities stripped before the deciding model writes the final decision
- **Four consensus modes wired through `DebateOrchestrator`:** `moderatorDecides`, `strictMajority`, `bestOfAll`, `votingThreshold` — with weighted voting when `providerWeights` is configured
- **Per-provider weighting:** `StrategyConfig.providerWeights` drives panel inclusion (weight 0 = excluded) and voting-threshold math; surfaced in the setup app
- **Setup app scaffold:** `jointchiefs-setup` SwiftUI executable target with Disclosure / Keys / Roles-&-Weights / Install / MCP-Config screens — all five views migrated to Agentdeck tokens (`agentBgPanel`, `agentDialogTitle`, `AgentInputStyle`, `AgentPill`, `AgentChip`, `agentPanel`, `.agentPrimary` / `.agentSecondary` / `.agentDanger` button styles)
- **Website live at [jointchiefs.ai](https://jointchiefs.ai/)** — static site deployed via Netlify. Source in the private `djfunboy/joint-chiefs-website` repo. Custom domain + Let's Encrypt cert configured.
- **60 tests passing** (unit + orchestrator integration + consensus-mode coverage + weighted-voting + APIKeyResolver with fake-keygetter harness)

Phases 1–3 and 5 are complete. Phase 6 (setup app) ships as a scaffold with
every view token-migrated; app-icon, signing, notarization, and real Keychain
round-trip QA remain. Phase 8 (MCP server) ships the scaffold + one tool; rate
limits and StrategyConfig wiring remain. Phase 10 (security + distribution) has
the website deployed; signing + notarization + Sparkle integration remain.
v2 security work is captured in tasks/SECURITY-AND-DIRECTION-PLAN-v2.md — with
the lean baseline correction: Apple Developer ID + notarization + Sparkle,
no YubiKey, no custom updater, no XPC.

## Pre-Build Checklist

- [x] Xcode 16+ installed with macOS 15 SDK
- [x] Apple Silicon Mac (M-series) — Intel Macs not supported
- [x] API keys available for at least 2 LLM providers
- [x] Swift ArgumentParser confirmed (Hummingbird deferred with Phase 4)
- [x] Data model designed (see DATA-MODEL.md)

---

## Phase 1: Project Scaffold & Provider Protocol ✅ COMPLETE

**Goal:** Xcode project compiles, provider protocol defined, one provider working.

**Steps:**
1. ✅ Create Xcode project with SwiftUI lifecycle
2. ✅ Add Swift Package dependencies (ArgumentParser)
3. ✅ Define `ReviewProvider` protocol and supporting types (`ProviderReview`, `Finding`, `ReviewContext`)
4. ✅ Implement `OpenAIProvider` as the first concrete provider
5. ✅ Write unit tests for provider with mocked HTTP responses

**Checkpoint:**
- [x] Project builds with zero warnings
- [x] `OpenAIProvider` can send a review request and parse the response
- [x] Provider tests pass
- [x] Types are fully defined (no `Any`)

---

## Phase 2: Additional Providers ✅ COMPLETE

**Goal:** All planned providers implemented and tested. **Scope expanded** — added Anthropic direct on top of the original three, so 5 providers ship (including Ollama).

**Steps:**
1. ✅ Implement `GeminiProvider` (Google AI API)
2. ✅ Implement `GrokProvider` (xAI API)
3. ✅ Implement `OllamaProvider` (local models, opt-in via `OLLAMA_ENABLED=1`)
4. ✅ Implement `AnthropicProvider` (added — Claude also moderates the debate)
5. ✅ Add provider factory/registry for dynamic provider creation from env vars
6. ✅ Write tests for each provider
7. ✅ Add SSE streaming to every provider

**Checkpoint:**
- [x] All 5 providers build and pass tests
- [x] Provider registry creates providers from environment configuration
- [x] Each provider handles errors gracefully (timeout, auth failure, rate limit)
- [x] All providers stream tokens via SSE

---

## Phase 3: Debate Orchestrator ✅ COMPLETE

**Goal:** Core review → debate → consensus pipeline working end-to-end. **Scope evolved** to hub-and-spoke architecture with Claude as moderator.

**Steps:**
1. ✅ Implement `DebateOrchestrator` with parallel initial review via `TaskGroup`
2. ✅ Implement hub-and-spoke debate round logic (Claude moderates, spokes respond)
3. ✅ Implement adaptive early-break when consensus is reached
4. ✅ Implement anonymous synthesis (strip model identities before final decision)
5. ✅ Implement `DebateTranscript` persistence to local files
6. ✅ Write orchestrator integration tests with mock providers

**Checkpoint:**
- [x] Orchestrator runs full cycle: parallel review → up to 5 debate rounds → Claude synthesis
- [x] Consensus output is structured with severity, agreement, recommendation
- [x] Transcripts persist to disk
- [x] Graceful degradation when 1 provider fails mid-review
- [x] Adaptive break triggers when models converge
- [x] Tests pass for all orchestrator paths

---

## Phase 4: Local HTTP Server ⏸️ DEFERRED

**Goal (original):** Hummingbird server accepting review requests, returning summaries.

**Why deferred:** Direct CLI invocation of the orchestrator works fine for solo use. A local HTTP server adds process management (launchd, port conflicts, start/stop) with no current benefit. Revisit only if a use case emerges that needs cross-process access (e.g., a menu bar app, multiple concurrent clients).

**Steps:** _(unchanged from v1.0, deferred)_
1. Embed Hummingbird server in the app, bind to localhost:7777
2. Implement `POST /review` endpoint
3. Implement `GET /status` health check
4. Implement `GET /models` to list configured providers
5. Server starts/stops with the app
6. Write server integration tests

---

## Phase 5: CLI Tool ✅ COMPLETE

**Goal:** `jointchiefs` command-line tool triggers reviews from any terminal. **Scope simplified** — calls the orchestrator directly instead of going through a local HTTP server (Phase 4 deferred).

**Steps:**
1. ✅ Create CLI target with Swift ArgumentParser
2. ✅ Implement `review` subcommand (reads file, runs orchestrator, streams output)
3. ✅ Implement `--stdin` flag for piped input (e.g., `git diff | jointchiefs review --stdin`)
4. ✅ Implement `--goal` flag for review focus
5. ✅ Stream SSE tokens to stdout live as each model speaks
6. ✅ Install to `/opt/homebrew/bin/jointchiefs`

**Checkpoint:**
- [x] `jointchiefs review src/example.swift` streams consensus summary to terminal
- [x] `echo "code" | jointchiefs review --stdin` works
- [x] Clear error message when API keys are missing
- [x] Installed at `/opt/homebrew/bin/jointchiefs`

---

## Phase 6: Setup App 🟢 SCAFFOLD + DESIGN-SYSTEM MIGRATION COMPLETE

**Goal:** Single-window SwiftUI app that lets end users add API keys and pick a
strategy without touching env vars or the CLI. One-shot installer pattern —
open once, configure, quit.

**Why now (vs. deferred in v1):** Two of v2's surfaces — the MCP server and
(soon) a Developer-ID-signed CLI — are now on a distribution path where end
users can't reasonably be asked to export env vars. The setup app is the
surface that writes keys to the Keychain (via the keygetter) and persists
`StrategyConfig`.

**Steps:**
1. ✅ `StrategyConfig` type defined in `JointChiefsCore` — now includes `providerWeights`
2. ✅ `StrategyConfigStore` load/save helpers
3. ✅ `APIKeyResolver` consumed by CLI + MCP (no direct env reads in hot paths); `writeViaKeygetter` / `deleteViaKeygetter` added for the setup app
4. ✅ `jointchiefs-keygetter` executable as the sole Keychain identity
5. ✅ SwiftUI app target (`jointchiefs-setup`): provider-keys screen with masked entry, Save, Test, and Delete per key
6. ✅ Roles & Weights panel: moderator picker, tiebreaker picker, consensus-mode picker, per-provider weight sliders (0 = excluded, >0 = voting weight), rounds/timeout sliders, voting-threshold slider
7. ✅ Install-location picker (default `/opt/homebrew/bin`, fallback `~/.local/bin`, custom via NSOpenPanel) — copies all three CLI binaries
8. ✅ PATH-on-install helper (detects destination on `$PATH`, shows the exact `export` line when missing)
9. ✅ MCP config snippet generator (keyless — reads destination path, outputs a standard `mcpServers` JSON block with a Copy button)
10. ✅ First-run data-handling disclosure screen (what is sent off-device, what stays local, what the app doesn't do)
11. ✅ All five views migrated to the Agentdeck design system — tokens in `JointChiefsSetup/DesignSystem/` (AgentdeckTokens, AgentdeckTypography, AgentdeckButtonStyle, AgentdeckComponents). No hex/CGFloat literals in any view. Components added: `AgentInputStyle` ViewModifier (dashed warm-tan focus), `agentPanel` View modifier, `AgentPill` (tinted status), `AgentChip` (picker replacement), `AgentSectionHeader` (uppercase eyebrow).

**Remaining before distribution (tracked under Phase 10):**
- App icon (`Resources/AppIcon.icns` + `CFBundleIconFile`). The bundle is functional without one; Finder just shows a generic icon.
- Code signing (`codesign --sign <Developer ID>`) on the four binaries, with `jointchiefs-keygetter` signed with `--identifier com.jointchiefs.keygetter` per the Keychain-ACL design.
- Notarization + stapling of the DMG artifact.
- End-to-end test of the key-write path against a real Keychain — currently smoke-tested via the keygetter's own exit-code contract.

**Build script** — `scripts/build-app.sh` runs `swift build -c release` and assembles `build/Joint Chiefs.app`:

```
Joint Chiefs.app/
└── Contents/
    ├── Info.plist                       (template in scripts/Info.plist; JC_VERSION/JC_BUILD env vars override)
    ├── MacOS/jointchiefs-setup          (bundle's main executable)
    └── Resources/
        ├── jointchiefs                  (CLI)
        ├── jointchiefs-mcp              (MCP stdio server)
        └── jointchiefs-keygetter        (APIKeyResolver.locateKeygetter finds it here)
```

`APIKeyResolver` and `InstallView` both do bundle-aware path discovery so the
keygetter and CLI sources are found via `Contents/Resources/` when the setup
app runs from the bundle, and via flat-sibling when it runs from
`.build/release/` during development.

---

## Phase 7: Transcript Viewer ⏸️ DEFERRED

**Goal (original):** Browse past review transcripts in the app.

**Why deferred:** Transcripts are written to local files and can be grep'd or opened directly. A dedicated viewer needs the menu bar app (Phase 6) to exist first, and there's no current pain point browsing past reviews.

**Steps:** _(unchanged from v1.0, deferred)_
1. Transcript list view (date, file, outcome, models used)
2. Transcript detail view (full debate, round by round)
3. Color-coded model responses
4. Search/filter by date, file, severity
5. Delete individual or bulk transcripts
6. Transcript detail shows consensus summary at top, full debate below

---

## Phase 8: MCP Server 🟡 IN PROGRESS

**Goal:** Native integration with any MCP-aware client via the MCP stdio protocol.

**Steps:**
1. ✅ Adopt `modelcontextprotocol/swift-sdk` (pinned exact `0.12.0`)
2. ✅ Stdio-only server (`jointchiefs-mcp`) with `joint_chiefs_review` tool
3. ✅ Smoke-tested — `initialize` + `tools/list` round-trip cleanly
4. ✅ Installed at `/opt/homebrew/bin/jointchiefs-mcp`
5. [ ] Wire `APIKeyResolver` (done) + `StrategyConfig` (in progress) into MCP tool invocation
6. [ ] Rate limits: 1 concurrent review, 30/hour cap, cancel on stdin close
7. [ ] Ship the standard `mcpServers` JSON snippet in the setup app and README

**Checkpoint:**
- [x] From an MCP client: calling `joint_chiefs_review` returns consensus summary (pre-rate-limit / pre-strategy)
- [x] MCP server starts/stops cleanly
- [ ] Rate limits enforced and logged to stderr
- [ ] Graceful cancellation on client disconnect

---

## Phase 9: Polish & Testing 🟡 PARTIAL

**Goal:** Production-ready quality.

**Steps:**
1. ✅ Orchestrator integration tests with mock providers (60 tests passing — includes per-consensus-mode coverage, tiebreaker routing, weighted voting, and `providerWeights` JSON round-trip)
2. ✅ Error handling audit for provider failure paths
3. ✅ APIKeyResolver env/keygetter precedence covered with fake-keygetter harness
4. [ ] Accessibility pass — VoiceOver/Dynamic Type on the setup app
5. [ ] Performance profiling: memory, latency per full review cycle
6. ✅ Documentation: README restructured for four-surface product (CLI, MCP, setup, keygetter); CLAUDE.md + all docs/*.md synced 2026-04-20

**Checkpoint:**
- [x] All tests pass (60 passing)
- [x] Zero warnings in build
- [ ] VoiceOver works on all interactive elements — with Phase 6
- [ ] Idle memory profiled
- [ ] Full review cycle latency measured with 3+ models, 5 adaptive rounds

---

## Phase 10: Security & Distribution 🟢 COMPLETE

**Goal:** Sign, notarize, and auto-update. Match the security baseline of
Chris's other 10 apps (Apple Developer ID + notarization + Sparkle).

**Source of truth:** `tasks/SECURITY-AND-DIRECTION-PLAN-v2.md` plus the user's
lean-baseline correction — the v2 plan's YubiKey/XPC/custom-updater items are
reversed in favor of the standard Apple Developer flow.

**Steps:**
1. ✅ Keychain-access prototype validating Option B (single signed keygetter)
2. ✅ `jointchiefs-keygetter` target building and producing expected exit codes
3. ✅ Public repo shipped — `github.com/djfunboy/joint-chiefs` (MIT)
4. ✅ Website shipped — `jointchiefs.ai` live via Netlify, custom domain + SSL configured; source in private `djfunboy/joint-chiefs-website` repo
5. ✅ Release signing — `scripts/build-app.sh` signs `jointchiefs-setup`, `jointchiefs`, `jointchiefs-mcp`, `jointchiefs-keygetter` with Developer ID; keygetter with `--identifier com.jointchiefs.keygetter` per the Keychain-ACL design
6. ✅ Notarization workflow — DMGs notarized + stapled since v0.1.0
7. ✅ DMG artifact — `Joint-Chiefs.dmg` shipped for v0.1.0 through v0.4.0 with app bundle + CLI binaries in `Contents/Resources/`
8. ✅ Sparkle integration — wired in v0.2.0 (commit `ae8dfe0`); v0.3.1 hotfix landed `install_name_tool` rpath patch in `scripts/build-app.sh` to fix the dyld-resolution failure that crashed v0.2.0 + v0.3.0 on cold-machine launch
9. ✅ URLSession redirect-authorization-stripping delegate — shared across providers (commit `57f7c7e`)
10. ✅ MCP rate limiting — 1 concurrent, 30/hour cap, cancel on stdin close (commit `57f7c7e`)
11. ✅ `SECURITY.md` written and shipped at repo root
12. ✅ Open-source README restructured for four surfaces (CLI, MCP, setup, keygetter)

---

## Post-Launch

- **Homebrew distribution:** `brew install jointchiefs`
- **Additional providers:** Mistral, DeepSeek
- **Team features:** Shared configs, review history sync
- **CI integration:** `jointchiefs review --ci` for pipeline use

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial build plan — 9 phases |
| 1.1 | 2026-04-08 | Phases 1-3, 5 marked complete. Phase 4, 6, 7 deferred. Phase 8 marked future. Phase 9 partial. Added "What's Built" section. Anthropic provider added to Phase 2 scope. Hub-and-spoke architecture and adaptive break documented in Phase 3. |
| 1.2 | 2026-04-18 | v2 scope: Phase 6 (setup app) and Phase 8 (MCP server) moved to in-progress. Added Phase 10 (security & distribution) with the lean security baseline. "What's Built" now lists keygetter + APIKeyResolver + StrategyConfig/Store + MCP server scaffold. Test count updated to 52. |
| 1.3 | 2026-04-19 | Phase 6 steps 5-10 complete: `jointchiefs-setup` SwiftUI target scaffolded with Disclosure / Keys / Roles-&-Weights / Install / MCP-Config screens. `StrategyConfig.providerWeights` added — 0 excludes a provider from the panel, positive values drive weighted voting in `.votingThreshold` mode. `APIKeyResolver` gained `writeViaKeygetter` / `deleteViaKeygetter`. `ReviewProvider.providerType` added so the orchestrator can resolve per-provider weight from a provider instance. Test count 52 → 60. Phase 9 step 1 checkpoint updated. |
| 1.4 | 2026-04-20 | Phase 6 step 11 complete: all five setup-app views migrated to Agentdeck tokens. `AgentdeckComponents.swift` added — `AgentInputStyle`, `agentPanel`, `AgentPill`, `AgentChip`, `AgentSectionHeader`. Phase 10 steps 3–4 complete: public app repo live at `github.com/djfunboy/joint-chiefs`, website shipped to `jointchiefs.ai` via Netlify (custom domain + SSL). Phase 9 step 6 complete: README + CLAUDE.md + all docs synced to four-surface reality and current test counts. Phase 9 checkpoint test count corrected 52 → 60. |
| 1.5 | 2026-04-25 | Phase 10 marked 🟢 COMPLETE — steps 5–11 reconciled with shipping reality (signing, notarization, DMG, Sparkle, redirect-stripping, MCP rate limits, SECURITY.md all landed across v0.1.0–v0.4.0). Sparkle integration note expanded to call out the v0.3.1 rpath hotfix that fixed the dyld-resolution failure in v0.2.0 + v0.3.0 cold-machine launches. |
