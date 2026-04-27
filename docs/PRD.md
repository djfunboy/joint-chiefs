# Joint Chiefs — Product Requirements Document

**Version:** 1.6
**Last Updated:** 2026-04-26

**Website:** [jointchiefs.ai](https://jointchiefs.ai/) (live)
**Repository:** [github.com/djfunboy/joint-chiefs](https://github.com/djfunboy/joint-chiefs) (public, MIT)

## Product Overview

### Vision

A "war room" for AI-assisted code review where multiple LLMs independently analyze code, debate their findings, and converge on consensus recommendations — exposed as an MCP server any MCP-aware AI client can spawn, plus a CLI for terminal and CI use, plus a one-shot macOS setup app that handles keys, strategy, and install.

### Problem

Solo developers using AI coding assistants get a single model's perspective on code review. Models have blind spots, biases, and different strengths. There's no easy way to get multiple AI opinions, have them challenge each other, and receive a unified recommendation — regardless of which AI client or CLI the developer is working in.

### Solution

Joint Chiefs is a four-surface product (CLI + stdio MCP server + macOS setup app + signed Keychain keygetter) that:
1. Exposes an MCP server (`jointchiefs-mcp`) any MCP-aware client can spawn over stdio, so the host LLM calls `joint_chiefs_review` like any other tool
2. Dispatches code to multiple configured LLM providers in parallel via `TaskGroup`
3. Runs structured debate rounds where models see anonymized prior findings and challenge each other
4. Synthesizes consensus into a concise summary returned to the caller
5. Writes full debate transcripts to local files for replay or pipeline inspection

### Business Model

Free, open-source tool for the developer community. No monetization planned.

## Target Users

### Primary: Solo Developers Using AI Coding Tools
- Use an AI coding assistant daily
- Want higher-quality code review than a single model provides
- Value consensus-driven recommendations over single opinions
- Have API keys for multiple LLM providers

### Secondary: Small Teams
- Want consistent, automated code review across the team
- Need a shared configuration for review standards and goals

## Core Features

### F1: Multi-Model Review Orchestration — DONE
Dispatch code to configured LLM providers simultaneously. Each spoke model performs an independent review without seeing others' findings.
- [x] Parallel API calls to all configured providers via `TaskGroup`
- [x] Configurable timeout per provider (default 120s)
- [x] Graceful degradation if a provider fails (proceed with available responses)
- [x] Each review tagged with provider name and model version
- [x] Six providers supported: OpenAI, Anthropic, Gemini, Grok, Ollama, plus any OpenAI-compatible local server (LM Studio / Jan / llama.cpp-server / Msty / LocalAI). Local options run side by side.

### F2: Structured Debate Rounds — DONE
Hub-and-spoke debate: Claude acts as moderator, spokes (OpenAI, Gemini, Grok) see anonymized prior findings and respond.
- [x] Configurable rounds (default 5 with adaptive early break)
- [x] Each round injects prior round's anonymized findings as context
- [x] Moderator (Claude) writes a brief between rounds
- [x] Adaptive break when positions converge

### F3: Consensus Synthesis — DONE
Claude (hub) synthesizes the debate into a structured final summary; falls back to code-based aggregation on failure.
- [x] Categorized findings by severity
- [x] Agreement level per finding
- [x] Unified recommended approach aligned to user-specified goals
- [x] Concise summary returned to the CLI

### F4: Universal CLI Trigger — DONE
CLI tool installed at `/opt/homebrew/bin/jointchiefs` (Apple Silicon Macs only). Runs directly — no local HTTP server required.
- [x] CLI tool: `jointchiefs review <path> [--goal "..."] [--context "..."]`
- [x] Streaming SSE output: tokens appear live in the terminal
- [x] Exit code 0 on success, 1 on failure
- [x] MCP server (`jointchiefs-mcp`) shipped — see F9 / Phase 8. HTTP API remains deferred (Phase 4); stdio-only MCP makes it unnecessary.

### F5: macOS Menu Bar App — DEFERRED
CLI-only works fine for solo use. Revisit if a GUI becomes necessary.

### F6: Setup App — DONE
Single-window SwiftUI executable (`jointchiefs-setup`) that ships alongside
the CLI and MCP server. Five sections, in display order:
- [x] **How to Use** (first screen) — orientation: what Joint Chiefs is + how to invoke from an AI client or terminal, with natural-language AI prompt and CLI examples (Copy buttons)
- [x] **API Keys** — masked entry, Save/Test/Delete per provider via the keygetter; curated top-5 model picker per provider via `ProviderType.availableModels`; Ollama and OpenAI-compatible local-server config
- [x] **Roles & Weights** — moderator, tiebreaker, consensus mode, per-provider weight sliders (0 = excluded), rounds & timeout sliders, voting threshold slider
- [x] **MCP Config** — keyless JSON snippet, Copy button, plus the natural-language AI playbook prompt; "Configured AI tools" panel (v0.5.0) showing per-tool MCP wire-up status
- [x] **Privacy** (last screen) — data-handling disclosure: what's sent to providers, what stays local, what the app refuses to do (no telemetry, no analytics); MIT-licensed link to the public repo
- [x] Silent CLI install on first launch (v0.3.0) — `SetupModel.installCLIIfNeeded()` copies the three binaries into `/opt/homebrew/bin` (or `~/.local/bin` fallback) at `RootView.task` time; replaced the earlier user-facing Install pane
- [x] All five views migrated to Agentdeck design tokens (no hex/CGFloat literals in any view); new design-system components: `AgentInputStyle`, `agentPanel`, `AgentPill`, `AgentChip`, `AgentSectionHeader`, `SetupPage`
- [x] Bundled in `Joint Chiefs.app` with `Contents/Resources/` binaries — DMGs notarized + stapled through v0.5.5
- [x] **"Configured AI tools" panel (v0.5.0)** — `MCPConfigScanner` walks home-dir conventional config locations (top-level dotfiles, `~/.<dir>/<file>`, `~/.config/<dir>/<file>`, `~/Library/Application Support/<dir>/<sub>/<file>`), structurally confirms each MCP-server stanza, and reports per-tool wire-up status with a "wired in M of N" pill. Detection is by stanza shape, never by client name.
- [x] **Sidebar update-status footer (v0.5.0)** — currently-running version + Sparkle-driven "Check for updates" / "update available" affordance with inline spinner during user-triggered checks.
- [ ] VoiceOver + Dynamic Type pass (tracked in Phase 9)
- [ ] Pre-flight validation: warn or disable Save when a provider is picked as moderator without a saved API key

### F7: Transcript Viewer — DEFERRED
Local transcript files written to disk. A UI for browsing them is deferred with the menu bar app.

### F8: Review Context — PARTIAL
- [x] `--goal` flag for user-specified review goals
- [x] `--context` flag for free-form additional context
- [ ] Automatic import/related-file inclusion
- [ ] Automatic git diff inclusion
- [ ] Automatic CLAUDE.md / project doc inclusion

## Technical Requirements

### Performance
- Initial review dispatch: < 2s from request to first API call
- Total review cycle (3 models, default 5 rounds with adaptive early-break): < 90s typical
- Setup app idle memory: < 100MB
- MCP tool-call overhead: < 100ms before the orchestrator dispatches (excludes LLM latency)
- Note: idle memory and full review-cycle latency have not been profiled yet (tracked in Phase 9 step 5)

### Reliability
- Graceful handling of provider timeouts and errors — orchestrator continues with remaining providers if one fails mid-round
- Transcript files written to local disk; reviews survive setup-app restarts because nothing in the review path runs in the setup app
- MCP server is stdio-only and stateless across invocations — no server process to crash; the host LLM owns the lifecycle
- No data loss on unexpected quit

### Security
- API keys stored in macOS Keychain, accessed exclusively by the signed `jointchiefs-keygetter` binary
- MCP server is stdio-only — no listening ports, no network transports (architecturally prohibited)
- CLI calls the orchestrator directly — no local HTTP server, no port binds
- No telemetry, no external connections except configured LLM APIs
- Code sent for review is not cached beyond the local transcript file

## User Flows

### Flow 1: First-Time Setup (end-user path via setup app)

**Requirements:** Apple Silicon Mac (M-series), macOS 15+.

1. Download the notarized DMG from `jointchiefs.ai` (or `brew install --cask joint-chiefs` once the tap is live)
2. Drag `Joint Chiefs.app` to `/Applications` and launch — CLI binaries install silently into `/opt/homebrew/bin` (or `~/.local/bin` fallback) on first launch
3. **How to Use** screen orients the user; click **Next — Add API Keys**
4. **API Keys** screen — paste each provider's key, click Test (live API probe via `ReviewProvider.testConnection()`); pick model from the curated top-5 picker if not the default. Local options (Ollama, OpenAI-compatible) are configured here too.
5. **Roles & Weights** — accept defaults (Claude moderator, 5 rounds, moderator-decides consensus) or tune
6. **MCP Config** — paste the JSON snippet into your AI client's MCP config, or paste the natural-language playbook prompt and let the host AI wire itself up; "Configured AI tools" panel confirms wire-up status
7. **Privacy** — review what's sent off-device, what stays local

### Flow 1b: First-Time Setup (developer path via env vars)

**Requirements:** Apple Silicon Mac (M-series), macOS 15+, Xcode 16+.

1. Build: `cd ~/Dropbox/Build/Joint\ Chiefs/JointChiefs && swift build -c release`
2. Install: `cp .build/release/jointchiefs .build/release/jointchiefs-mcp .build/release/jointchiefs-keygetter /opt/homebrew/bin/`
3. Add API keys to `~/.zshrc`:
   ```
   export OPENAI_API_KEY="sk-..."
   export GEMINI_API_KEY="..."
   export GROK_API_KEY="..."
   export ANTHROPIC_API_KEY="sk-ant-..."   # also serves as the moderator
   ```
4. Verify: `jointchiefs models`
5. Ready — `jointchiefs review <file>` works from anywhere

### Flow 2: Trigger Review from an AI Client Terminal
1. User asks their AI client: "Have the Joint Chiefs review src/auth.swift"
2. The AI runs: `jointchiefs review src/auth.swift --goal "security review"`
3. Real-time streaming output shows:
   - Each general reviewing in parallel
   - Claude synthesizing brief between rounds
   - Each general's debate position
   - Adaptive break when positions converge
   - Final consensus from Claude
4. The AI reads the result and presents to user

## Design Principles

1. **Summary out, transcript in.** The CLI/API returns only the consensus summary. Full debate lives in the app.
2. **Universal trigger.** Any tool that can run a shell command or make an HTTP request works. No lock-in.
3. **Opinionated defaults, full control.** Works great out of the box. Every parameter is configurable.
4. **Graceful degradation.** If 1 of 3 models fails, the review continues with 2. Never block on a single provider.
5. **Privacy first.** Localhost only. No telemetry. API keys in Keychain.
6. **Research-backed debate.** The structured debate mechanism is grounded in Multi-Agent Debate (MAD) research (Liang et al., 2023; [arXiv:2305.19118](https://arxiv.org/abs/2305.19118)), which demonstrates that adversarial collaboration between multiple LLMs produces more accurate and reliable outputs than single-model inference or self-reflection. See `docs/RESEARCH.md` for implementation details.

## Success Metrics

- Review cycle completes in < 90s for 3 models, 2 rounds
- Consensus summary fits in < 2000 characters
- Works with any AI CLI or MCP-aware client without modification
- Zero data leaves the machine except to configured LLM APIs

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial PRD |
| 1.1 | 2026-04-09 | Updated F1-F8 status (F1-F4 DONE, F5-F7 DEFERRED, F8 PARTIAL); rewrote Flow 1 to reflect CLI build/install process; rewrote Flow 2 to show streaming output; dropped Flow 3 (menu bar app deferred) |
| 1.2 | 2026-04-19 | F6 (Setup App) promoted from DEFERRED to DONE (scaffold) — `jointchiefs-setup` ships Disclosure/Keys/Roles-&-Weights/Install/MCP-Config sections; per-provider weighting (0 excludes, >1 amplifies voting weight) landed in `StrategyConfig`. Bundle wrapping + accessibility pass remain tracked in Phases 9 and 10. |
| 1.3 | 2026-04-20 | Added website + repository references to the header. F6 updated to reflect the Agentdeck design-system migration landing across all five views — `AgentInputStyle`, `agentPanel`, `AgentPill`, `AgentChip`, `AgentSectionHeader` shipped as reusable components in `JointChiefsSetup/DesignSystem/AgentdeckComponents.swift`. |
| 1.4 | 2026-04-25 | Reconciled local-server contradictions. Solution rewritten around the four-surface MCP-first product. F4's MCP-wrapper bullet flipped to ✅ (shipped via Phase 8). Technical Requirements rewritten — removed "local server response" / "server auto-restarts" / "binds to localhost" lines; replaced with stdio-MCP-aware reliability + security text. |
| 1.5 | 2026-04-25 | F6 promoted from "DONE (scaffold)" to plain DONE — bundle + DMG checkbox flipped from `[ ]` → `[x]` (DMGs notarized + stapled through v0.4.0). Added two v0.5.0 checkboxes: the "Configured AI tools" panel surfacing per-tool MCP wire-up status, and the sidebar update-status footer. |
| 1.6 | 2026-04-26 | Vision rewritten — dropped the "macOS menu bar app" framing that contradicted F5's DEFERRED status; now describes the four-surface MCP-first product. F1 bullet added for the 6th provider (OpenAI-compatible / LM Studio). F6 section list rewritten in display order — Usage / Keys / Roles & Weights / MCP Config / Privacy (was Disclosure / Keys / Roles / Install / MCP Config) — and silent CLI install on first launch documented (Install pane was replaced in v0.3.0). Added the still-open pre-flight moderator-key validation gap as an unchecked F6 item. Performance line corrected: default is 5 rounds with adaptive early-break, not 2. Flow 1 split into end-user (setup app) path and developer (env-var) path. |
