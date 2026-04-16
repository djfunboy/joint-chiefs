# Joint Chiefs — Product Requirements Document

**Version:** 1.1
**Last Updated:** 2026-04-09

## Product Overview

### Vision

A "war room" for AI-assisted code review where multiple LLMs independently analyze code, debate their findings, and converge on consensus recommendations — all orchestrated from a macOS menu bar app and triggered from any LLM CLI tool.

### Problem

Solo developers using AI coding assistants get a single model's perspective on code review. Models have blind spots, biases, and different strengths. There's no easy way to get multiple AI opinions, have them challenge each other, and receive a unified recommendation — especially across different CLI tools (Claude Code, Codex, Gemini CLI, Grok).

### Solution

Joint Chiefs is a macOS menu bar app that:
1. Runs a local server accepting review requests from any LLM CLI
2. Dispatches code to multiple configured LLM providers in parallel
3. Runs structured debate rounds where models see and challenge each other's findings
4. Synthesizes consensus into a concise summary returned to the caller
5. Stores full debate transcripts for browsing in the app

### Business Model

Free, open-source tool for the developer community. No monetization planned.

## Target Users

### Primary: Solo Developers Using AI Coding Tools
- Use Claude Code, Codex, Gemini CLI, or similar daily
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
- [ ] HTTP API / MCP wrapper — deferred with menu bar app

### F5: macOS Menu Bar App — DEFERRED
CLI-only works fine for solo use. Revisit if a GUI becomes necessary.

### F6: Settings UI — DEFERRED
Environment variables (`OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `ANTHROPIC_API_KEY`, optional model overrides) cover configuration today.

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
- Total review cycle (2 rounds, 3 models): < 90s typical
- Menu bar app memory: < 100MB idle
- Local server response: < 100ms overhead (excluding LLM latency)

### Reliability
- Server auto-restarts on crash
- Graceful handling of provider timeouts and errors
- Transcript storage survives app restarts (SwiftData persistence)
- No data loss on unexpected quit

### Security
- API keys stored in macOS Keychain, not plaintext
- Local server binds to localhost only (not exposed to network)
- No telemetry, no external connections except configured LLM APIs
- Code sent for review is not stored beyond the transcript

## User Flows

### Flow 1: First-Time Setup

**Requirements:** Apple Silicon Mac (M-series), macOS 15+, Xcode 16+.

1. Build the CLI: `cd ~/Dropbox/Build/Joint\ Chiefs/JointChiefs && swift build -c release`
2. Install: `cp .build/release/jointchiefs /opt/homebrew/bin/jointchiefs`
3. Add API keys to `~/.zshrc`:
   ```
   export OPENAI_API_KEY="sk-..."
   export GEMINI_API_KEY="..."
   export GROK_API_KEY="..."
   export ANTHROPIC_API_KEY="sk-ant-..."  # also serves as deciding model
   ```
4. Verify: `jointchiefs models`
5. Ready — `jointchiefs review <file>` works from anywhere

### Flow 2: Trigger Review from Claude Code Terminal
1. User asks Claude: "Have the Joint Chiefs review src/auth.swift"
2. Claude runs: `jointchiefs review src/auth.swift --goal "security review"`
3. Real-time streaming output shows:
   - Each general reviewing in parallel
   - Claude synthesizing brief between rounds
   - Each general's debate position
   - Adaptive break when positions converge
   - Final consensus from Claude
4. Claude reads the result and presents to user

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
- Works with Claude Code, Codex, Gemini CLI, and Grok CLI without modification
- Zero data leaves the machine except to configured LLM APIs

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial PRD |
| 1.1 | 2026-04-09 | Updated F1-F8 status (F1-F4 DONE, F5-F7 DEFERRED, F8 PARTIAL); rewrote Flow 1 to reflect CLI build/install process; rewrote Flow 2 to show streaming output; dropped Flow 3 (menu bar app deferred) |
