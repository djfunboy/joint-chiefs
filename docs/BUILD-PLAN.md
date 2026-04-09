# Joint Chiefs — Build Plan

**Version:** 1.1
**Last Updated:** 2026-04-08

## What's Built

Joint Chiefs is a working CLI tool. Running `jointchiefs review <file> --goal "..."` in any terminal produces a streaming, multi-model code review with a final consensus summary.

- **CLI installed** at `/usr/local/bin/jointchiefs` — direct execution, no local HTTP server required
- **5 providers live:** OpenAI, Google Gemini, xAI Grok, Anthropic Claude, plus optional Ollama
- **Streaming SSE** from every provider — tokens appear live as each model speaks
- **Hub-and-spoke debate:** OpenAI / Gemini / Grok are spokes, Claude is the moderator/decider
- **Adaptive rounds:** up to 5 debate rounds with early break when consensus is reached
- **Anonymous synthesis:** model identities stripped before Claude writes the final decision (reduces bias)
- **Config via env vars:** `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `ANTHROPIC_API_KEY`, `OLLAMA_ENABLED=1`, plus `*_MODEL` overrides
- **34 tests passing** (unit + orchestrator integration with mock providers)

Phases 1-5 are complete. Phase 6+ (menu bar app, transcript viewer, MCP wrapper) are deferred — the CLI with env-var config covers the solo-use workflow.

## Pre-Build Checklist

- [x] Xcode 16+ installed with macOS 15 SDK
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
6. ✅ Install to `/usr/local/bin/jointchiefs`

**Checkpoint:**
- [x] `jointchiefs review src/example.swift` streams consensus summary to terminal
- [x] `echo "code" | jointchiefs review --stdin` works
- [x] Clear error message when API keys are missing
- [x] Installed at `/usr/local/bin/jointchiefs`

---

## Phase 6: Menu Bar App & Settings UI ⏸️ DEFERRED

**Goal (original):** Working menu bar app with settings for providers and review parameters.

**Why deferred:** Environment variables cover provider configuration fully for a solo developer. A settings UI is nice-to-have but adds Keychain integration, SwiftData persistence, launch-at-login, and menu bar state management — all for convenience Chris doesn't need yet. Revisit if configuration friction becomes real.

**Steps:** _(unchanged from v1.0, deferred)_
1. Menu bar icon with status (idle / reviewing / error)
2. Settings window: add/remove/reorder providers
3. API key entry with Keychain storage
4. Test Connection button per provider
5. Review parameters UI (rounds, timeout, severity threshold, default goal)
6. Launch at login toggle
7. Server port configuration

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

## Phase 8: MCP Server Wrapper ⏸️ FUTURE

**Goal:** Claude Code native integration via MCP.

**Why future (not just deferred):** This is the highest-value next phase once the CLI is proven in daily use. Would expose `joint_chiefs_review` as a native tool inside Claude Code, letting Claude autonomously request a multi-model review during a coding session instead of Chris shelling out manually.

**Steps:** _(unchanged from v1.0, future work)_
1. Create thin MCP server (stdio) that wraps the orchestrator directly
2. Expose `joint_chiefs_review` tool with code, filePath, goal parameters
3. Register in Claude Code MCP config
4. Document setup in README

**Checkpoint:**
- [ ] From Claude Code: calling `joint_chiefs_review` returns consensus summary
- [ ] MCP server starts/stops cleanly
- [ ] Streaming output forwarded through MCP where supported

---

## Phase 9: Polish & Testing 🟡 PARTIAL

**Goal:** Production-ready quality.

**Steps:**
1. ✅ Orchestrator integration tests with mock providers (34 tests passing)
2. ✅ Error handling audit for provider failure paths
3. [ ] Accessibility pass — N/A until menu bar app lands (Phase 6)
4. [ ] Performance profiling: memory, latency per full review cycle
5. [ ] Documentation: README with setup instructions

**Checkpoint:**
- [x] All tests pass (34 passing)
- [x] Zero warnings in build
- [ ] VoiceOver works on all interactive elements — deferred with Phase 6
- [ ] Idle memory profiled
- [ ] Full review cycle latency measured with 3+ models, 5 adaptive rounds

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
