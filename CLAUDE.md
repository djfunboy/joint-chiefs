# Joint Chiefs

Multi-model AI code review orchestrator. CLI tool that sends code to multiple LLMs, runs a structured hub-and-spoke debate with Claude as moderator/decider, and streams a consensus summary back to the terminal. Grounded in Multi-Agent Debate (MAD) research showing debate improves factuality and reasoning over single-model output.

## Current State

- **Phases 1-5 complete.** Phase 6+ (menu bar app, transcript viewer, MCP wrapper) deferred — CLI-only works fine for solo use.
- **CLI installed** at `/opt/homebrew/bin/jointchiefs` (Apple Silicon only). Runs directly without a local HTTP server.
- **5 providers working:** OpenAI, Google Gemini, xAI Grok, Anthropic Claude, plus optional Ollama for local models.
- **Streaming SSE** on every provider — tokens appear live in the terminal as each model speaks.
- **Hub-and-spoke debate:** spokes (OpenAI, Gemini, Grok) produce findings; Claude (hub) moderates rounds and writes the final anonymous synthesis.
- **34 tests passing.** No performance profiling done yet.

## Key Rules

- **Swift strict typing.** No `Any` unless truly unavoidable.
- **@Observable macro.** macOS 15+ target. Use `@State`, `@Environment`, `@Bindable`. Never mix with `ObservableObject`.
- **@MainActor** on all classes that publish UI state.
- **Service pattern:** `@Environment` injection (no singletons). Same pattern used across our other macOS apps.
- **Build system:** Swift Package Manager. Minimum target macOS 15.0 (Sonoma). **Apple Silicon only** — Intel Macs are not supported.
- **Design system:** Agentdeck (monospace-as-identity, warm-charcoal palette). See `docs/DESIGN-SYSTEM.md`. Every Color, Font, spacing, and radius used in `JointChiefsSetup` must come from the `Agentdeck*` token files in `Sources/JointChiefsSetup/DesignSystem/`. Never hardcode a hex or a CGFloat in a view.

## Tech Stack

- **CLI:** Swift executable (`jointchiefs`), ArgumentParser, streaming output
- **Providers:** OpenAI, Google Gemini, xAI Grok, Anthropic Claude, Ollama — all via REST with SSE streaming
- **Orchestrator:** Hub-and-spoke — Claude moderates; other models are spokes
- **Storage:** Local transcript files (SwiftData deferred with the menu bar app)

## Configuration

Environment variables (set in shell profile):

- `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `ANTHROPIC_API_KEY`
- Optional model overrides: `OPENAI_MODEL`, `GEMINI_MODEL`, `GROK_MODEL`, `ANTHROPIC_MODEL`
- `OLLAMA_ENABLED=1` to include local Ollama models in the debate

**Default models:** `gpt-5.4`, `gemini-3.1-pro-preview`, `grok-3`, `claude-opus-4-6`
**Default debate settings:** 5 rounds with adaptive early break, 120s per-request timeout

### Local API Keys

Stored in `tasks/api-keys.local.md` (gitignored). Also exported in `~/.zshrc` for shell sessions.

## Architecture

```
Joint Chiefs/
├── CLAUDE.md
├── JointChiefs/                ← Xcode project
│   ├── Models/                 ← Provider types, transcripts
│   ├── Services/               ← Providers, orchestrator
│   └── CLI/                    ← jointchiefs executable
├── JointChiefsTests/           ← 34 tests
├── docs/
│   ├── ARCHITECTURE.md
│   ├── VALUE-PROPOSITION.md
│   ├── BUILD-PLAN.md
│   ├── PRD.md
│   ├── DATA-MODEL.md
│   └── KNOWN-ISSUES.md
└── tasks/
    └── lessons.md
```

## Key Patterns

- **Provider protocol:** All LLM providers conform to `ReviewProvider` with a streaming `review(code:context:) async throws -> AsyncStream<ReviewChunk>`.
- **Hub-and-spoke orchestrator:** `DebateOrchestrator` fans out to spokes in parallel via `TaskGroup`, feeds anonymized findings to Claude as moderator, runs up to 5 rounds with an adaptive break when consensus is reached, then Claude writes the final synthesis.
- **Anonymous synthesis:** Model identities are stripped before the final decision to reduce bias toward any single provider.

## Project Docs

- `docs/ARCHITECTURE.md` — System design, component diagram, data flow
- `docs/VALUE-PROPOSITION.md` — Product positioning, target audience, messaging
- `docs/BUILD-PLAN.md` — Phased implementation plan with checkpoint statuses
- `docs/PRD.md` — Product requirements, features, acceptance criteria
- `docs/DATA-MODEL.md` — Type definitions, transcript schema
- `docs/DESIGN-SYSTEM.md` — Agentdeck tokens + SwiftUI component mappings (mandatory reading before any UI change)
- `docs/KNOWN-ISSUES.md` — Active bugs, tech debt, documentation gaps
- `tasks/lessons.md` — Corrections and patterns (reviewed every session)
