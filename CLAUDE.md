# Joint Chiefs

> **Canonical instruction file.** AGENTS.md is a symlink to this file.

**Goal:** Public MIT-licensed open-source tool. Success = adoption and acquisition value, not revenue. Reliability beats features — prefer minimal correct changes. Don't propose monetization, premium tiers, or scale infrastructure unless asked.

Multi-model AI code review orchestrator. Four surfaces (CLI, stdio MCP server, macOS setup app, keygetter binary) built on one `JointChiefsCore` engine. Hub-and-spoke debate with Claude as moderator; streams consensus summary. Grounded in MAD research.

**Website:** https://jointchiefs.ai/ (source: private `djfunboy/joint-chiefs-website` repo — this repo is the app)
**Latest release:** v0.5.11 — `claude-fable-5` default moderator; refreshed provider model lists. 93 tests. CFBundleVersion `1777000009`.
**Next session:** read the most recent `tasks/SESSION-HANDOFF-*.md` (gitignored; local-only).

## Stack & Architecture

- **Build system:** Swift Package Manager. Minimum target **macOS 15.0 (Sequoia). Apple Silicon only** — no Intel support.
- **Packages:** `JointChiefsCore` (models/providers/orchestrator/credential store/APIKeyResolver), `JointChiefsCLI` (`jointchiefs`), `JointChiefsMCP` (`jointchiefs-mcp`, stdio), `JointChiefsSetup` (SwiftUI setup app), `JointChiefsKeygetter` (`jointchiefs-keygetter`)
- **MCP dependency:** `modelcontextprotocol/swift-sdk` pinned **exact 0.12.0**
- **State management:** `@Observable` macro + `@State`/`@Environment`/`@Bindable`. Never mix with `ObservableObject`.
- **Service pattern:** `@Environment` injection — no singletons.
- **Design system:** Agentdeck (monospace-as-identity, warm-charcoal). All colors/fonts/spacing/radii in `JointChiefsSetup` MUST come from `Agentdeck*` token files in `Sources/JointChiefsSetup/DesignSystem/`. Read `docs/DESIGN-SYSTEM.md` before any UI change. Never hardcode hex or CGFloat.
- **Providers:** OpenAI, Anthropic Claude, Google Gemini, xAI Grok, Ollama, OpenAI-compatible (LM Studio/Jan/llama.cpp-server/Msty/LocalAI) — all via REST + SSE streaming
- **Storage:** `StrategyConfig` JSON → `~/Library/Application Support/Joint Chiefs/strategy.json` (0600); API keys → `credentials.json` (same dir, 0600) via keygetter only

## Key Rules

- **Streaming SSE always.** Non-streaming LLM calls are banned — they time out. Every provider uses `URLSession.bytes(for:)`.
- **Stdio-only MCP.** Network transports (HTTP, SSE, WebSocket) prohibited — security depends on MCP client owning stdio.
- **Never enumerate specific MCP clients or AI CLIs** in docs/UI/comments/commits. Use "any MCP client" / "any AI CLI".
- **No Sentry or telemetry** — deliberately omitted to avoid privacy-policy/tracking disclosure obligations. Do not add any analytics.
- **Keygetter is the sole credential accessor.** All `credentials.json` reads/writes go through `jointchiefs-keygetter` via `Process`. `LegacyKeychainStore` exists only for the one-time `keygetter migrate` path (v0.5.7 migration).
- **Setup-guide / llms.txt sync.** The in-app AI prompt in `MCPConfigView.swift` (`aiPrompt`) tells the host AI to fetch `https://jointchiefs.ai/setup-guide.md`. Any change to binary paths, install commands, providers, tool names, rate limits, restart guidance, failure modes, or verification steps requires parallel updates to `setup-guide.md` AND `llms.txt` in the website repo. Treat the trio as one logical surface.
- **Voice for long-form content.** Articles, blog posts, marketing copy — load `~/Library/CloudStorage/Dropbox/Build/Content/voice-of-chris-doyle.md` first.
- **`@MainActor`** on all classes that publish UI state.

## Configuration

API keys via `APIKeyResolver`:
1. **Env vars** (CI only): `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `ANTHROPIC_API_KEY`
2. **Keygetter → `credentials.json`** (end-user default): written by setup app, read headlessly by CLI + MCP server.

Optional model overrides: `OPENAI_MODEL`, `GEMINI_MODEL`, `GROK_MODEL`, `ANTHROPIC_MODEL`, `CONSENSUS_MODEL`
Local: `OLLAMA_ENABLED=1`, `OLLAMA_MODEL` (default `llama3`); `OPENAI_COMPATIBLE_BASE_URL` + `OPENAI_COMPATIBLE_MODEL`
**Defaults:** `gpt-5.5`, `gemini-3.5-flash`, `grok-4.3`, `claude-fable-5` · 5 rounds, 120s timeout, adaptive early break
Dev keys: `tasks/api-keys.local.md` (gitignored) + `~/.zshrc` exports

## Repository Separation

Never commingle. Two distinct repos:

| Repo | Visibility | Remote | Checkout |
|---|---|---|---|
| **App** (`joint-chiefs`) | **PUBLIC (MIT)** | `github.com/djfunboy/joint-chiefs` | `~/Dropbox/Build/Joint Chiefs/` |
| **Website** (`joint-chiefs-website`) | **PRIVATE** | `github.com/djfunboy/joint-chiefs-website` | `~/Dropbox/Build/Joint Chiefs Website/` |

Website auto-deploys to jointchiefs.ai via Netlify on every `git push origin main`.

## Pre-Release Review (PUBLIC repo — mandatory, skip none)

Before any release action (tag, DMG build, `gh release`, appcast, cask bump, or any push crossing the release boundary), run all five parts and report to Chris:

1. **Folder scan** — `*.local.md`, `.env*`, `Sparkle*.key`/EdDSA private material, `tasks/SESSION-HANDOFF-*.md`, hostname-leaking absolute paths, customer data, third-party credentials. Verify all gitignored.
2. **Diff scan** — grep every new commit since last tag for: `sk-[A-Za-z0-9]{20,}`, `ghp_`, `gho_`, `xoxb-`, `BEGIN [A-Z ]*PRIVATE KEY`, `Authorization: Bearer`, `aws_secret`, `password\s*=`, real API key prefixes.
3. **Code review** — pre-commit + code-review checklists from `~/.claude/rules/checklists.md`. Zero warnings, all tests pass.
4. **Cold-machine smoke test** — `rm -rf "/Applications/Joint Chiefs.app"`, mount fresh DMG, drag-install, launch, confirm first-run window appears. Signing/notarization verdicts alone don't catch dyld/rpath failures.
5. **Doc scan** — CLAUDE.md current-state line, `docs/BUILD-PLAN.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/KNOWN-ISSUES.md`, `README.md` reflect shipping state. Version bumped in source. No stale internal refs.

## Project Docs

`docs/ARCHITECTURE.md` · `docs/VALUE-PROPOSITION.md` · `docs/BUILD-PLAN.md` · `docs/PRD.md` · `docs/DATA-MODEL.md` · `docs/DESIGN-SYSTEM.md` · `docs/KNOWN-ISSUES.md` · `tasks/lessons.md`
