# Joint Chiefs

Multi-model AI code review orchestrator. Four surfaces — CLI, stdio MCP server, macOS setup app, and a single Keychain-access binary — all built from one `JointChiefsCore` engine. Sends code to multiple LLMs, runs a structured hub-and-spoke debate with Claude as moderator/decider, and streams a consensus summary back. Grounded in Multi-Agent Debate (MAD) research showing debate improves factuality and reasoning over single-model output.

**Website:** https://jointchiefs.ai/ (live — source in the private `djfunboy/joint-chiefs-website` repo; this repo is the app)
**Latest release:** v0.5.2 — Sparkle build-number hotfix. v0.5.0 shipped with `CFBundleVersion=5` while pre-v0.5.0 releases used a Unix-timestamp scheme; Sparkle's natural-numeric comparator then declared v0.4.0 "newer" than v0.5.0 and prompted fresh installs to downgrade. v0.5.2 locks `CFBundleVersion` at `1777000000` and bakes a regression check into `scripts/build-app.sh` so non-monotonic build numbers are impossible by construction. No code changes — same binaries as v0.5.0. Built on v0.5.0's "Configured AI tools" panel + sidebar update-status footer, plus v0.4.0's LM Studio support, MCP progress visibility, and Ollama timeout fix.
**Next session:** start by reading the most recent `tasks/SESSION-HANDOFF-*.md` (gitignored; local-only).

## Current State

- **Phases 1–3, 5, 8, and 10 complete.** Phase 6 (setup app) ships its full five-view installer with the v0.5.0 "Configured AI tools" panel showing per-tool MCP wire-up status; remaining items are accessibility (VoiceOver / Dynamic Type) and a real-Keychain end-to-end round-trip test, both tracked under Phase 9. Website live at jointchiefs.ai with notarized DMGs + Sparkle appcast through v0.5.2.
- **CLI installed** at `/opt/homebrew/bin/jointchiefs` (Apple Silicon only). Calls the orchestrator directly — no local HTTP server.
- **MCP server** at `jointchiefs-mcp` — stdio-only, wraps the orchestrator via `modelcontextprotocol/swift-sdk` pinned exact 0.12.0. Spawned by any MCP-aware client via JSON-RPC over stdio.
- **Setup app** at `jointchiefs-setup` — one-shot SwiftUI installer (Usage / Keys / Roles & Weights / MCP Config / Privacy). All five views use Agentdeck tokens end-to-end. CLI binaries install silently on first launch — no manual destination picker. Keychain access goes through the keygetter only.
- **Keygetter** at `jointchiefs-keygetter` — the single signed identity authorized to read/write Joint Chiefs' Keychain items. CLI, MCP server, and setup app all invoke it via `Process`.
- **6 providers working:** OpenAI, Anthropic Claude, Gemini, Grok, plus two local options — Ollama (native protocol) and any OpenAI-compatible server (LM Studio, Jan, llama.cpp-server, Msty, LocalAI). Local options are independent — both can run side by side.
- **Streaming SSE** on every provider — tokens appear live as each model speaks.
- **Hub-and-spoke debate:** spokes produce findings; the moderator (Claude by default) synthesizes rounds and writes the final anonymous consensus. 4 consensus modes: `moderatorDecides`, `strictMajority`, `bestOfAll`, `votingThreshold` (with per-provider weighting).
- **80 tests passing.** No performance profiling done yet.

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
- **Setup-guide / llms.txt sync.** The in-app AI prompt at `JointChiefs/Sources/JointChiefsSetup/Views/MCPConfigView.swift` (`aiPrompt`) tells the host AI to fetch `https://jointchiefs.ai/setup-guide.md` when wire-up gets stuck. Any change to that prompt — binary path, install command, providers list, tool name, rate limits, restart guidance, failure modes, verification step — requires a parallel update to `setup-guide.md` in the website repo. Capability or surface-area changes also update `llms.txt` there. Treat the trio (in-app prompt → `setup-guide.md` → `llms.txt`) as one logical surface; never edit one without checking the others.
- **Pre-release review (public repo).** This repo is public + MIT — anything committed is permanently visible to the world. Before any release action (tag, DMG build, `gh release`, appcast entry, cask bump, or any push that crosses the release boundary), run a full five-part review and report findings to Chris before proceeding. Skip none.
  1. **Folder scan** for files that shouldn't be in a public repo: `*.local.md` (gitignored — verify still untracked), `.env*`, `Sparkle*.key` or any EdDSA private material, anything in `tasks/` matching `SESSION-HANDOFF-*.md` (gitignored), hostname-leaking absolute paths, customer/business data, third-party credentials.
  2. **Diff scan** of every new commit since the last release tag for accidentally-included secrets. Patterns to grep for in the diff: `sk-[A-Za-z0-9]{20,}`, `ghp_`, `gho_`, `xoxb-`, `BEGIN [A-Z ]*PRIVATE KEY`, `Authorization: Bearer`, `aws_secret`, `password\s*=`, real API key prefixes for OpenAI / Anthropic / Google / xAI.
  3. **Code review** per `~/.claude/rules/checklists.md` — pre-commit + code-review checklists end-to-end. Build with zero warnings, all tests passing, no force-unwraps in new code, errors surface to the user, no retain cycles, MARK sections present, access control correct.
  4. **Cold-machine smoke test** per the v0.3.1 hotfix lesson. `rm -rf "/Applications/Joint Chiefs.app"` (no fallback copy), mount the just-built DMG, drag-install, launch, confirm the first-run window actually appears. Signing + notarization + `spctl -a` verdicts are necessary but not sufficient — they don't catch dyld/rpath failures.
  5. **Doc scan** — `CLAUDE.md` current-state line, `docs/BUILD-PLAN.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/KNOWN-ISSUES.md`, `README.md` reflect the actual shipping state. Version bumped where it appears in source. No stale internal-only references. No broken cross-doc links.

## Tech Stack

- **CLI:** Swift executable (`jointchiefs`), ArgumentParser, streaming output
- **MCP server:** Swift executable (`jointchiefs-mcp`), stdio transport, `modelcontextprotocol/swift-sdk` 0.12.0
- **Setup app:** Swift executable (`jointchiefs-setup`), SwiftUI + `@Observable`, Agentdeck design system
- **Keygetter:** Swift executable (`jointchiefs-keygetter`), sole Keychain identity
- **Providers:** OpenAI, Anthropic Claude, Google Gemini, xAI Grok, Ollama, OpenAI-compatible (LM Studio / Jan / llama.cpp-server / Msty / LocalAI) — all via REST with SSE streaming
- **Orchestrator:** Hub-and-spoke — Claude moderates by default; spokes can be any of the other providers
- **Storage:** `StrategyConfig` JSON at `~/Library/Application Support/Joint Chiefs/strategy.json` (file mode 0600); local transcript files for reviews; API keys in Keychain via keygetter

## Configuration

API keys are resolved via `APIKeyResolver`:

1. **Environment variables** (CI-only fallback): `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `ANTHROPIC_API_KEY`
2. **Keygetter → Keychain** (end-user default): written by the setup app's Save button, read by the CLI + MCP server at invocation time

Optional model overrides (env vars): `OPENAI_MODEL`, `GEMINI_MODEL`, `GROK_MODEL`, `ANTHROPIC_MODEL`, `CONSENSUS_MODEL`.

`OLLAMA_ENABLED=1` and `OLLAMA_MODEL` (default `llama3`) to include a local Ollama model. `OPENAI_COMPATIBLE_BASE_URL` and `OPENAI_COMPATIBLE_MODEL` (CI override; the setup app's Roles & Weights screen is the normal config path) to include any OpenAI-compatible server alongside or instead of Ollama.

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

## Repository Separation (important)

Two distinct repos — never commingle. Don't copy website files into this repo, or vice versa. If you're unsure which repo a file belongs in, stop and ask.

| Repo | Visibility | Remote | Checkout |
|---|---|---|---|
| **App** (this repo: `joint-chiefs`) | **PUBLIC** (MIT) | `github.com/djfunboy/joint-chiefs` | `~/Dropbox/Build/Joint Chiefs/` |
| **Website** (`joint-chiefs-website`) | **PRIVATE** | `github.com/djfunboy/joint-chiefs-website` | `~/Dropbox/Build/Joint Chiefs Website/` |

The website is deployed to [jointchiefs.ai](https://jointchiefs.ai) via Netlify. **Auto-deploy is wired** — every `git push origin main` on the website repo triggers a Netlify build + deploy. No manual step.

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
