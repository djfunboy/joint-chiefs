# Joint Chiefs

Multi-model AI code review orchestrator. Four surfaces — CLI, stdio MCP server, macOS setup app, and a single Keychain-access binary — all built from one `JointChiefsCore` engine. Sends code to multiple LLMs, runs a structured hub-and-spoke debate with Claude as moderator/decider, and streams a consensus summary back. Grounded in Multi-Agent Debate (MAD) research showing debate improves factuality and reasoning over single-model output.

**Website:** https://jointchiefs.ai/ (live — source in the private `djfunboy/joint-chiefs-website` repo; this repo is the app)
**Next session mission:** get the app fully ready to launch on the website. Start by reading `tasks/SESSION-HANDOFF-2026-04-21.md`.

## Current State

- **Phases 1–5 complete.** Phase 6 (setup app) has shipped as a scaffold with every view migrated to Agentdeck tokens. Phase 8 (MCP server) is in progress — scaffolding + `joint_chiefs_review` tool ship, rate limits + strategy wiring still to land. Phase 10 (security + distribution) is in progress — website live at jointchiefs.ai with 10 articles + share buttons, first notarized DMG + real appcast entry still pending.
- **CLI installed** at `/opt/homebrew/bin/jointchiefs` (Apple Silicon only). Calls the orchestrator directly — no local HTTP server.
- **MCP server** at `jointchiefs-mcp` — stdio-only, wraps the orchestrator via `modelcontextprotocol/swift-sdk` pinned exact 0.12.0. Spawned by any MCP-aware client via JSON-RPC over stdio.
- **Setup app** at `jointchiefs-setup` — one-shot SwiftUI installer (Disclosure / Keys / Roles-&-Weights / Install / MCP-Config). All five views use Agentdeck tokens end-to-end. Keychain access goes through the keygetter only.
- **Keygetter** at `jointchiefs-keygetter` — the single signed identity authorized to read/write Joint Chiefs' Keychain items. CLI, MCP server, and setup app all invoke it via `Process`.
- **5 providers working:** OpenAI, Gemini, Grok, Anthropic Claude, plus optional Ollama for local models.
- **Streaming SSE** on every provider — tokens appear live as each model speaks.
- **Hub-and-spoke debate:** spokes produce findings; the moderator (Claude by default) synthesizes rounds and writes the final anonymous consensus. 4 consensus modes: `moderatorDecides`, `strictMajority`, `bestOfAll`, `votingThreshold` (with per-provider weighting).
- **60 tests passing.** No performance profiling done yet.

## Key Rules

- **Swift strict typing.** No `Any` unless truly unavoidable.
- **@Observable macro.** macOS 15+ target. Use `@State`, `@Environment`, `@Bindable`. Never mix with `ObservableObject`.
- **@MainActor** on all classes that publish UI state.
- **Service pattern:** `@Environment` injection (no singletons). Same pattern used across our other macOS apps.
- **Build system:** Swift Package Manager. Minimum target macOS 15.0 (Sequoia). **Apple Silicon only** — Intel Macs are not supported.
- **Design system:** Agentdeck (monospace-as-identity, warm-charcoal palette). See `docs/DESIGN-SYSTEM.md`. Every Color, Font, spacing, and radius used in `JointChiefsSetup` must come from the `Agentdeck*` token files in `Sources/JointChiefsSetup/DesignSystem/`. Never hardcode a hex or a CGFloat in a view.
- **Streaming SSE always.** Non-streaming LLM calls are banned — they time out. Every provider uses `URLSession.bytes(for:)`.
- **Never enumerate specific MCP clients or AI CLIs.** Use "any MCP client" / "any AI CLI" in docs, UI, comments, and commit messages. The product is MCP-spec-conformant.
- **Stdio-only MCP.** Network transports (HTTP, SSE, WebSocket) are prohibited — every security assumption depends on the MCP client owning the MCP server's stdio.
- **Voice for any long-form content.** Articles, blog posts, marketing copy — always load `/Users/chrisdoyle/Library/CloudStorage/Dropbox/Build/Content/voice-of-chris-doyle.md` first. It's the canonical voice for anything user-facing.

## Tech Stack

- **CLI:** Swift executable (`jointchiefs`), ArgumentParser, streaming output
- **MCP server:** Swift executable (`jointchiefs-mcp`), stdio transport, `modelcontextprotocol/swift-sdk` 0.12.0
- **Setup app:** Swift executable (`jointchiefs-setup`), SwiftUI + `@Observable`, Agentdeck design system
- **Keygetter:** Swift executable (`jointchiefs-keygetter`), sole Keychain identity
- **Providers:** OpenAI, Google Gemini, xAI Grok, Anthropic Claude, Ollama — all via REST with SSE streaming
- **Orchestrator:** Hub-and-spoke — Claude moderates by default; spokes can be any of the other providers
- **Storage:** `StrategyConfig` JSON at `~/Library/Application Support/Joint Chiefs/strategy.json` (file mode 0600); local transcript files for reviews; API keys in Keychain via keygetter

## Configuration

API keys are resolved via `APIKeyResolver`:

1. **Environment variables** (CI-only fallback): `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `ANTHROPIC_API_KEY`
2. **Keygetter → Keychain** (end-user default): written by the setup app's Save button, read by the CLI + MCP server at invocation time

Optional model overrides (env vars): `OPENAI_MODEL`, `GEMINI_MODEL`, `GROK_MODEL`, `ANTHROPIC_MODEL`, `CONSENSUS_MODEL`.

`OLLAMA_ENABLED=1` and `OLLAMA_MODEL` (default `llama3`) to include a local Ollama model.

Strategy (moderator / tiebreaker / consensus mode / rounds / timeout / per-provider weights) is persisted as `StrategyConfig` — see `docs/DATA-MODEL.md`.

**Default models:** `gpt-5.4`, `gemini-3.1-pro-preview`, `grok-3`, `claude-opus-4-6`
**Default debate settings:** 5 rounds with adaptive early break, 120s per-request timeout

### Local API Keys (dev only)

Stored in `tasks/api-keys.local.md` (gitignored). Also exported in `~/.zshrc` for shell sessions.

## Architecture

```
Joint Chiefs/                          (github.com/djfunboy/joint-chiefs — public, MIT)
├── CLAUDE.md
├── README.md
├── LICENSE
├── JointChiefs/                       ← Swift Package
│   ├── Package.swift
│   ├── Sources/
│   │   ├── JointChiefsCore/           ← Models, providers, orchestrator, keychain, APIKeyResolver
│   │   ├── JointChiefsCLI/            ← jointchiefs executable
│   │   ├── JointChiefsMCP/            ← jointchiefs-mcp executable (stdio)
│   │   ├── JointChiefsSetup/          ← jointchiefs-setup SwiftUI executable
│   │   │   └── DesignSystem/          ← Agentdeck tokens + components (mandatory)
│   │   └── JointChiefsKeygetter/      ← jointchiefs-keygetter executable
│   └── Tests/JointChiefsCoreTests/    ← 60 tests
├── docs/                              ← see Project Docs below
├── prototypes/keychain-access/        ← empirical validation of the keygetter design
├── scripts/                           ← build-app.sh + Info.plist template
└── tasks/
    └── lessons.md                     ← corrections log
```

The website is a separate repo: **`djfunboy/joint-chiefs-website`** (private) → deployed to [jointchiefs.ai](https://jointchiefs.ai) via Netlify.

## Key Patterns

- **Provider protocol:** All LLM providers conform to `ReviewProvider` and expose `providerType` so the orchestrator can map a provider instance back to its `StrategyConfig` weight.
- **Hub-and-spoke orchestrator:** `DebateOrchestrator` fans out to spokes in parallel via `TaskGroup`, feeds anonymized findings to the moderator, runs up to 5 rounds with an adaptive break when consensus is reached, then synthesizes the final summary through one of four consensus modes.
- **Anonymous synthesis:** Model identities are stripped before the final decision to reduce bias toward any single provider.
- **Single Keychain identity:** All Keychain reads/writes go through `jointchiefs-keygetter`. Other binaries call it via `Process`. Empirically validated in `prototypes/keychain-access/` — a single trusted identity avoids cross-binary ACL churn when any surface updates in place.

## Project Docs

- `docs/ARCHITECTURE.md` — System design, component diagram, data flow, security model
- `docs/VALUE-PROPOSITION.md` — Product positioning, target audience, messaging
- `docs/BUILD-PLAN.md` — Phased implementation plan with checkpoint statuses
- `docs/PRD.md` — Product requirements, features, acceptance criteria
- `docs/DATA-MODEL.md` — `StrategyConfig` (live) + SwiftData schema (deferred menu bar app)
- `docs/DESIGN-SYSTEM.md` — Agentdeck tokens + SwiftUI component mappings (mandatory reading before any UI change)
- `docs/KNOWN-ISSUES.md` — Active bugs, follow-ups, QA gaps
- `tasks/lessons.md` — Corrections and patterns (reviewed every session)
