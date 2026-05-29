# Joint Chiefs — Architecture

**Version:** 1.8
**Last Updated:** 2026-05-27

**Website:** [jointchiefs.ai](https://jointchiefs.ai/) — deployed via Netlify. Source in the private `djfunboy/joint-chiefs-website` repo.
**App repo:** [github.com/djfunboy/joint-chiefs](https://github.com/djfunboy/joint-chiefs) (public, MIT).

## System Overview

Joint Chiefs uses a **hub-and-spoke** debate model. The "generals" (any of
OpenAI, Anthropic Claude, Gemini, Grok, Ollama, or an OpenAI-compatible local
server such as LM Studio / Jan / llama.cpp-server / Msty / LocalAI) each review
the code independently and send their findings to the moderator (Claude by
default, configurable via `StrategyConfig.moderator`). The moderator synthesizes
the round's findings, sends the anonymized synthesis back to the generals for
the next round, and — once consensus is reached or max rounds hit — writes the
final summary. A code-based `ConsensusBuilder` is available as a fallback if the
moderator is unavailable.

Every review/debate/moderator prompt is centralized in `ReviewPrompts.swift`
and hard-codes an **anti-over-engineering calibration** posture. A hub-and-spoke
debate naturally escalates "thoroughness" — each round a model justifies its
turn by finding more, so output drifts toward nitpicks and speculative
over-engineering. The prompts counter this with an explicit proportionality bar
(what clears the bar for a finding, honest severity definitions), a debate
framed as *converge-and-cut* rather than accumulate, and a moderator instructed
to cut anything not worth acting on before shipping.

```
┌──────────────────────────┐
│     jointchiefs CLI      │
└────────────┬─────────────┘
             │
             ▼
  ┌──────────────────────┐
  │  DebateOrchestrator  │
  └──────────┬───────────┘
             │
             │  Round N: fan out to generals
             ▼
  ┌─────────────────────────────────────────────────────┐
  │  Generals (independent, parallel review)            │
  │                                                     │
  │  ┌──────┐ ┌──────┐ ┌────┐ ┌──────┐ ┌─────────────┐  │
  │  │OpenAI│ │Gemini│ │Grok│ │Ollama│ │OpenAI-compat│  │
  │  └──┬───┘ └──┬───┘ └─┬──┘ └──┬───┘ └──────┬──────┘  │
  └─────┼────────┼───────┼───────┼─────────────┼────────┘
        │        │       │       │             │
        └────────┴───────┼───────┴─────────────┘
                         │  Reports
                         ▼
           ┌───────────────────┐
           │ Claude (moderator)│
           │                   │
           │  Synthesizes this │
           │  round's findings │
           └─────────┬─────────┘
                     │
          ┌──────────┴──────────┐
          │                     │
          ▼                     ▼
  Next round synthesis    Converged?
  (back to generals)           │
                               ▼
                    ┌────────────────────┐
                    │  Final consensus   │
                    │  from Claude (or   │
                    │  code fallback via │
                    │  ConsensusBuilder) │
                    └────────────────────┘
```

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Setup app | SwiftUI + `@Observable` (Agentdeck design system) | One-shot installer for keys, strategy, MCP config, CLI install |
| CLI | Swift ArgumentParser | `jointchiefs` command-line tool |
| MCP server | `modelcontextprotocol/swift-sdk` 0.12.0 (stdio transport) | `jointchiefs-mcp` exposes `joint_chiefs_review` |
| Credential access | Single binary (`jointchiefs-keygetter`) | Sole reader/writer of the local API-key file; one-time legacy-Keychain migration |
| Persistence | `StrategyConfig` JSON + local transcript files | `~/Library/Application Support/Joint Chiefs/strategy.json` (mode 0600). SwiftData reserved for the deferred menu bar app (PRD F5) |
| Secrets | `credentials.json` (mode 0600, via keygetter) | API key storage — `~/Library/Application Support/Joint Chiefs/credentials.json` |
| Networking | URLSession | LLM API calls |
| API Calls | `URLSession.bytes` (SSE streaming) | Stream LLM responses, no timeouts |
| Auto-update | Sparkle 2.x (app bundle only) | Bundled CLI + MCP binaries re-installed via setup app on update |
| Minimum target | macOS 15 (Apple Silicon only) | `@Observable` macro |

## Project Structure

Reflects the four-surface product as it currently ships.

```
JointChiefs/
├── Package.swift
├── Sources/
│   ├── JointChiefsCore/
│   │   ├── Models/
│   │   │   └── StrategyConfig.swift         (moderator/tiebreaker/consensus/rounds/timeout/providerWeights)
│   │   ├── Errors/
│   │   └── Services/
│   │       ├── APIKeyResolver.swift         (env → keygetter; read/write/delete/migrate; CLI + MCP + setup app funnel through it)
│   │       ├── CredentialStore.swift         (0600 credentials.json file store — the live API-key backend)
│   │       ├── LegacyKeychainStore.swift     (read-only access to v0.5.6 Keychain keys; migration path only)
│   │       ├── StrategyConfigStore.swift    (load/save ~/Library/Application Support/…)
│   │       ├── ProviderFactory.swift        (panel assembly; filters `weight == 0`; moderator/tiebreaker builders)
│   │       ├── ConsensusBuilder.swift
│   │       ├── DebateOrchestrator.swift
│   │       ├── ReviewPrompts.swift          (single source of truth for review/debate/moderator prompts + calibration)
│   │       └── Providers/  (OpenAI, Anthropic, Gemini, Grok, Ollama, OpenAICompatible — each exposes providerType)
│   ├── JointChiefsCLI/                       (executable: jointchiefs)
│   ├── JointChiefsMCP/                       (executable: jointchiefs-mcp — stdio only)
│   ├── JointChiefsKeygetter/                 (executable: jointchiefs-keygetter)
│   └── JointChiefsSetup/                     (executable: jointchiefs-setup — SwiftUI one-shot installer)
│       ├── SetupApp.swift                   (@main, AppKit delegate for foreground activation)
│       ├── Model/
│       │   ├── SetupModel.swift             (@Observable @MainActor state; legacy-key migration + credential probe + silent CLI install on launch)
│       │   ├── UpdaterService.swift         (Sparkle wrapper; drives sidebar update-status footer)
│       │   └── MCPConfigScanner.swift       (generic MCP-server detector for the "Configured AI tools" panel)
│       └── Views/                           (RootView, UsageView, KeysView, RolesWeightsView, MCPConfigView, DisclosureView)
└── Tests/JointChiefsCoreTests/
```

## Key Components

### ReviewProvider Protocol

```swift
protocol ReviewProvider: Sendable {
    var name: String { get }
    var model: String { get }
    var providerType: ProviderType { get }
    func review(code: String, context: ReviewContext) async throws -> ProviderReview
    func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview
    func testConnection() async throws -> Bool
}
```

All providers conform to this protocol. Each provider:
- Wraps a single LLM API (OpenAI, Anthropic Claude, Gemini, xAI, Ollama, or an OpenAI-compatible endpoint)
- Handles its own authentication and request formatting
- Returns a structured `ProviderReview` with typed findings

### DebateOrchestrator

The core engine. Manages the full review lifecycle:

1. **Parallel Review Phase:** Sends code to all configured providers simultaneously via `TaskGroup`. Each returns independent findings.
2. **Debate Rounds:** For each round (configurable, default 5 with adaptive early-break on convergence):
   - Sends all prior findings to each provider
   - Each provider can agree, disagree, revise, or raise new findings
   - Tracks position changes across rounds
3. **Consensus Phase:** Passes all findings + debate history to the moderator (Claude by default) via one of four `ConsensusMode`s — `moderatorDecides`, `strictMajority`, `bestOfAll`, `votingThreshold` — producing the final `ConsensusSummary`. `ConsensusBuilder` provides a code-based fallback.
4. **Storage:** Persists full `DebateTranscript` to local files under the user's caches. Returns only `ConsensusSummary` to caller.

### CLI Tool

Swift ArgumentParser executable that calls `DebateOrchestrator` directly — no
local HTTP server in between.

```bash
# Basic review
jointchiefs review src/auth.swift

# With goal
jointchiefs review src/auth.swift --goal "security audit"

# Review a git diff
git diff | jointchiefs review --stdin --goal "pre-commit check"

# List configured models (status only)
jointchiefs models

# Probe each configured provider's API
jointchiefs models --test
```

### MCP Server

Standalone stdio executable (`jointchiefs-mcp`) that wraps the orchestrator
directly. Uses `modelcontextprotocol/swift-sdk` pinned to exact `0.12.0`.
Spawned by any MCP client via JSON-RPC over stdin/stdout. Exposes a single
`joint_chiefs_review` tool.

**Stdio-only invariant.** Network transports (HTTP, SSE, WebSocket) are
architecturally prohibited — every security assumption depends on the MCP
client owning our stdio by definition.

### Setup App

Single-window SwiftUI executable (`jointchiefs-setup`) that onboards users
without requiring shell surgery. Five sections, navigable via a sidebar
(in display order):

- **How to Use** — first screen. Orients the user to what Joint Chiefs is —
  a panel of LLMs that debate a code review and produce one consensus
  summary — and shows exactly how to invoke it from a terminal or any AI
  client with MCP configured. Includes the natural-language AI prompt and
  CLI invocation examples with Copy buttons.
- **API Keys** — masked entry per provider. Save writes to the credential
  file via `APIKeyResolver.writeViaKeygetter` and reads it back to verify the
  round-trip; Test resolves the key and runs `ReviewProvider.testConnection()`;
  Delete calls `APIKeyResolver.deleteViaKeygetter`. Each provider row has a Model picker
  driven by `ProviderType.availableModels` (top 5 curated). Ollama and any
  OpenAI-compatible local server (LM Studio, Jan, llama.cpp-server, Msty,
  LocalAI) are configured here too — both are independent and can run side
  by side.
- **Roles & Weights** — moderator picker, tiebreaker picker, consensus-mode
  picker, rounds and timeout sliders, per-provider weight sliders (0 = excluded
  from panel, 1.0 = default vote, up to 3.0 = triple vote). Dirty-state
  indicator plus an explicit Save action persisting to
  `StrategyConfigStore.save(_:)`.
- **MCP Config** — generates a standard `mcpServers` JSON snippet that points
  at the installed `jointchiefs-mcp` path. Works with any MCP client. No key
  material in the snippet — keys live in the local credential file, resolved
  at tool-call time. The "Configured AI tools" panel (v0.5.0) walks home-dir conventional
  config locations, structurally confirms each MCP-server stanza, and reports
  per-tool wire-up status with a "wired in M of N" pill. Detection is by
  stanza shape (JSON `mcpServers` map, TOML `[mcp_servers...]` table) — never
  by client name.
- **Privacy** — last screen. Data-handling disclosure: what's sent to
  providers, what stays local, what the app refuses to do (no telemetry, no
  analytics). MIT-licensed link to the public repo.

CLI binaries (`jointchiefs`, `jointchiefs-mcp`, `jointchiefs-keygetter`) are
installed silently into `/opt/homebrew/bin` (or `~/.local/bin` fallback) on
first launch via `SetupModel.installCLIIfNeeded()` — no manual destination
picker, no install button. Keeps the wizard focused on configuration, not
file copying.

The sidebar footer (v0.5.0) shows the currently-running app version and a
Sparkle-driven "Check for updates" / "update available" affordance with an
inline spinner during user-triggered checks. `UpdaterService` skips Sparkle
init when running outside an app bundle so dev builds via `swift run` don't
hit the "updater failed to start" modal.

The setup app reaches the credential file *only* through the keygetter for the
same reason the CLI and MCP server do — see the keygetter section below.

### Credential storage: `CredentialStore` and `LegacyKeychainStore`

API keys are stored in `~/Library/Application Support/Joint Chiefs/credentials.json`
— a flat JSON object (`{ "openai": "sk-…", … }`) written with file mode `0600`
and a parent directory of `0700`. `CredentialStore` mirrors `StrategyConfigStore`:
same app-support directory resolution, atomic write, permission hardening.

This replaced the macOS Keychain as of v0.5.7. The Keychain's access approval
is an interactive GUI prompt; a headless CLI/MCP session (SSH, cron, no
logged-in user) cannot show or answer it, so saved keys were unreadable in
exactly the contexts the product targets. A `0600` file has no session or
prompt dependency, and FileVault provides encryption at rest. `LegacyKeychainStore`
remains for one purpose only: the one-time `keygetter migrate` path, which
reads any v0.5.6-era Keychain items and moves them into the file. Nothing
writes the Keychain anymore.

### APIKeyResolver and `jointchiefs-keygetter`

Instead of embedding credential-file access in every binary, only one binary
(`jointchiefs-keygetter`) reads or writes `credentials.json`. The CLI and MCP
server invoke it via `Process` and read the key from stdout — the file's
access path is auditable in exactly one place.

Resolution priority:

1. **Environment variable** (CI escape hatch). `OPENAI_API_KEY`,
   `ANTHROPIC_API_KEY`, etc. If set and non-empty, it wins.
2. **Keygetter invocation.** `APIKeyResolver.locateKeygetter()` tries
   `$JOINTCHIEFS_KEYGETTER_PATH`, the caller's sibling directory, and
   `/Applications/Joint Chiefs.app/Contents/Resources/`. The keygetter is
   spawned with `read <account>`; its stdout is the raw key (no trailing
   newline).
3. **Nil.** Provider is treated as "not configured."

Exit code contract (callers depend on these):

| Exit | Meaning |
|---|---|
| 0 | Success — key on stdout |
| 2 | Credential-file failure (unreadable, corrupt, write error) |
| 3 | Item not found (resolver returns nil, not an error) |
| 4 | Legacy: Keychain interaction required (unused by the file store; retained so older callers still map the code) |
| 5 | Other error |
| 6 | Legacy key found in the old Keychain — needs migration (resolver throws `legacyKeysNeedMigration`) |
| 64 | Usage error |

## Data Flow

```
1. Request arrives (CLI invocation or MCP tool call)
         │
2. DebateOrchestrator.startReview()
         │
3. ┌─────┬──────┬─────┬─────┬───────┬──────────────┐
   │     │      │     │     │       │              │  Parallel: independent reviews
   ▼     ▼      ▼     ▼     ▼       ▼              ▼
 OpenAI Claude Gemini Grok Ollama OpenAI-compatible
   │     │      │     │     │       │
   └─────┴──────┴─────┴─────┴───────┘
         │
4. Collect findings, build round 1 context
         │
5. ┌─────┬──────┬─────┬─────┬───────┬──────────────┐
   │     │      │     │     │       │              │  Debate round 1: challenge findings
   ▼     ▼      ▼     ▼     ▼       ▼              ▼
 OpenAI Claude Gemini Grok Ollama OpenAI-compatible
   │     │      │     │     │       │
   └─────┴──────┴─────┴─────┴───────┘
         │
6. Repeat for configured rounds
         │
7. Moderator synthesis (ConsensusBuilder fallback)
         │
   ┌─────┴──────┐
   │             │
   ▼             ▼
Summary      Transcript
(returned)   (written to local file)
```

## Debate Methodology

Joint Chiefs implements a structured multi-agent debate protocol grounded in academic research on improving LLM reasoning through adversarial collaboration.

**Research basis:** Liang et al., "Encouraging Divergent Thinking in Large Language Models through Multi-Agent Debate" (2023). [arXiv:2305.19118](https://arxiv.org/abs/2305.19118) | [GitHub](https://github.com/Skytliang/Multi-Agents-Debate)

The paper demonstrates that multi-agent debate between LLMs significantly improves factual accuracy and reasoning quality compared to single-model inference or single-model self-reflection. Joint Chiefs applies four key principles from and inspired by this research:

### 1. Adaptive Break

Debate stops early when positions converge. The MAD paper identifies a failure mode where forcing continued debate after consensus actually degrades output quality. Joint Chiefs monitors agreement levels across rounds and terminates debate when all active findings reach unanimous or near-unanimous positions, avoiding unnecessary rounds that introduce noise.

### 2. Tit-for-Tat Engagement

Models must directly address each prior finding by title, taking a clear position: agree, challenge, or revise. No restating or summarizing without engagement. This mirrors the MAD protocol's requirement for substantive responses to opposing arguments, preventing models from ignoring inconvenient findings.

### 3. Degeneration of Thought (DoT) Prevention

The MAD paper's central finding: when a single model reflects on its own output, confidence increases regardless of whether the answer is correct. This "Degeneration of Thought" problem means self-reflection is unreliable. Joint Chiefs avoids DoT by using multiple independent models with different architectures and training data. Each model's blind spots are challenged by models that don't share those blind spots.

### 4. Judge Arbitration

When debate rounds complete without full consensus, a deciding model (Claude by default) reads the full debate transcript and synthesizes the final summary. The judge evaluates reasoning quality — not just majority opinion. A well-argued minority position from one model can override a weakly-justified majority. This corresponds to the MAD paper's judge role, which resolves deadlocks by assessing argument strength.

## Streaming API Calls

All providers use `URLSession.bytes(for:)` for Server-Sent Events (SSE)
streaming rather than waiting for the full response body.

- **No more timeouts.** Earlier versions of Joint Chiefs hit `URLSession`
  timeouts when a provider took a long time to produce a full response.
  Switching to byte-stream reading eliminates the idle timeout because the
  socket is continuously receiving data.
- **Progress signal.** Token-by-token reading means we know a model is
  actively responding even during long generations — useful both for CLI
  output and for orchestration logic that otherwise can't distinguish
  "slow" from "dead."
- **Consistent across providers.** OpenAI, Anthropic, Gemini, Grok, Ollama,
  and any OpenAI-compatible server all stream through the same
  `AsyncStream<ReviewChunk>` shape, so the orchestrator doesn't need
  provider-specific buffering logic.

## Configuration

Provider API keys are resolved via `APIKeyResolver` (env var → keygetter). The
env var is a CI-only escape hatch; end users add keys via the setup app, which
writes them to the `credentials.json` file through the keygetter.

Other settings — moderator selection, consensus mode, tiebreaker, rounds,
timeouts, rate limits, per-provider weights — live in `StrategyConfig` and are
persisted to `~/Library/Application Support/Joint Chiefs/strategy.json`
(file mode 0600). CLI flags override per-invocation.
`StrategyConfigStore.load()` falls back silently to `.default` when the file
is missing or malformed.

### Per-Provider Weighting

`StrategyConfig.providerWeights: [ProviderType: Double]` drives two behaviors:

- **Panel inclusion.** A weight of `0.0` excludes the provider from the spoke
  panel at `ProviderFactory.buildPanel` time, regardless of whether an API key
  is available. Missing entries are treated as `1.0` (v1 behavior).
- **Weighted voting.** In `ConsensusMode.votingThreshold`, the survival ratio
  is computed as `sum(weights of providers who raised a finding) / sum(weights
  of providers that responded in the final round)`. Equal weights reduce to
  the pre-weighting raw-count ratio, so existing configs keep their exact
  behavior.

On disk the field serializes as a readable JSON object
(`{"openAI": 1.5, "gemini": 0}`) rather than Swift's default flat-array form
for enum-keyed dictionaries. See the custom `init(from:)` / `encode(to:)` in
`StrategyConfig.swift`.

| Variable | Purpose | Default |
|---|---|---|
| `OPENAI_API_KEY` | OpenAI authentication | (required to enable OpenAI) |
| `OPENAI_MODEL` | OpenAI model override | `gpt-5.5` |
| `GEMINI_API_KEY` | Google Gemini authentication | (required to enable Gemini) |
| `GEMINI_MODEL` | Gemini model override | `gemini-3.5-flash` |
| `GROK_API_KEY` | xAI Grok authentication | (required to enable Grok) |
| `GROK_MODEL` | Grok model override | `grok-4.3` |
| `ANTHROPIC_API_KEY` | Anthropic authentication — also serves as deciding model | (required to enable Claude) |
| `ANTHROPIC_MODEL` | Claude model override | `claude-opus-4-8` |
| `OLLAMA_ENABLED` | Set to `1` to force-include / `0` to force-exclude the local Ollama general (overrides `StrategyConfig.ollama.enabled`) | unset (use `StrategyConfig`) |
| `OLLAMA_MODEL` | Ollama model override | `llama3` |
| `OPENAI_COMPATIBLE_BASE_URL` | Force-enable an OpenAI-compatible local server (LM Studio, Jan, llama.cpp-server, Msty, LocalAI). CI override for `StrategyConfig.openAICompatible`. | unset |
| `OPENAI_COMPATIBLE_MODEL` | Model identifier as the local server exposes it | unset |
| `CONSENSUS_MODEL` | Override the Claude model used for consensus synthesis | falls back to `ANTHROPIC_MODEL` |

Claude (via `ANTHROPIC_API_KEY`) plays a dual role: it reviews code as one
of the generals and also acts as the moderator/decider for the final
synthesis. `CONSENSUS_MODEL` lets you split these — e.g. use a smaller
Claude model for per-round reviews and a larger one for the final call.

## Security Model

- **API keys** live in a permission-locked file (`credentials.json`, mode
  `0600`), accessed exclusively by the `jointchiefs-keygetter` binary. The CLI
  and MCP server invoke it via `Process` and drop the key immediately after
  use — see the `CredentialStore`, `APIKeyResolver`, and keygetter sections
  above. FileVault encrypts the file at rest; a `0600` file is the standard
  server-side credential pattern and the only one that works headless.
- **Env vars are CI-only fallback.** Documented as such in SECURITY.md and
  the setup app's first-run screen. Not the default path for end users.
- **No local HTTP server.** The CLI calls the orchestrator directly; the MCP
  server is stdio-only. Nothing binds a port.
- **No telemetry.** No analytics. No external connections except configured
  LLM API endpoints.
- **Code sent for review** is stored only in the local transcript files. User
  can delete transcripts at any time.
- **Provider responses** are not cached beyond the transcript.
- **Distribution** uses Apple Developer ID signing + notarization, with
  Sparkle for updates — matching the security baseline of Chris's other apps.
  No custom updater, no YubiKey root, no XPC.

## Performance Targets

A full hub-and-spoke debate runs initial parallel reviews + up to 5 debate
rounds (with adaptive early break) + moderator synthesis across multiple
LLMs. Realistic latency depends heavily on panel size and whether a local
model is in the mix; cloud-only panels finish in minutes, panels that
include a local model (Ollama, LM Studio, llama.cpp-server, Msty, LocalAI)
extend further because a single local-model round can itself be a multi-
minute wall-clock cost. None of those long runs are "stuck" — they're
active inference. Progress is surfaced through three side channels (MCP
`notifications/progress`, `jointchiefs-mcp` stderr heartbeats, and a JSON
status file at `~/Library/Caches/Joint Chiefs/current-review.json`) so a
host UI showing only an elapsed-time counter doesn't make a working run
look indistinguishable from a hang.

| Metric | Target |
|---|---|
| Request to first API call | < 2s |
| Full review (cloud-only, 3-model panel, adaptive break) | minutes (typical) |
| Full review (panel includes a local model) | 15+ minutes typical (inference cost of the local model) |
| App idle memory | < 100MB |
| Server overhead per request | < 100ms |
| Transcript storage per review | < 500KB |

## Development Environment

- **Xcode 16+** with Swift 6
- **macOS 15+** for development and deployment
- **Swift Package Manager** for dependencies
- **Dependencies:** `swift-argument-parser` (CLI flags), `modelcontextprotocol/swift-sdk` (pinned exact `0.12.0` — MCP stdio), `Sparkle` (auto-update for the app bundle)

## Distribution

- **App repo:** public at [github.com/djfunboy/joint-chiefs](https://github.com/djfunboy/joint-chiefs) — MIT licensed.
- **Website:** [jointchiefs.ai](https://jointchiefs.ai/) — static HTML + shared `styles.css`, Agentdeck palette matching the setup app. Hosted on Netlify; source is a separate private repo (`djfunboy/joint-chiefs-website`) with auto-deploy on push to main. Netlify manages the apex domain + `www` alias + Let's Encrypt cert.
- **Release artifact:** notarized + stapled DMG containing `Joint Chiefs.app` with the four binaries in `Contents/Resources/` (CLI/MCP/keygetter) and `Contents/MacOS/jointchiefs-setup`. Shipped through v0.5.10; SHA-256 wired into `Casks/joint-chiefs.rb`.
- **Sparkle appcast** at [jointchiefs.ai/appcast.xml](https://jointchiefs.ai/appcast.xml) — EdDSA-signed entries for v0.5.0, v0.5.2, v0.5.3, v0.5.4, v0.5.5, v0.5.6, v0.5.7, v0.5.8, v0.5.9, and v0.5.10. Pre-v0.5.0 entries were stripped after the v0.5.0 build-number bug (see `tasks/lessons.md` 2026-04-26 — they used Unix-timestamp `CFBundleVersion` values that exceeded v0.5.0's sequential `5`, causing Sparkle to "downgrade" fresh installs).
- **Auto-update path:** Sparkle for the app bundle. The `UpdaterService` wrapper drives the sidebar update-status footer. No custom updater for the CLI or MCP binaries — Sparkle replaces the bundle and the bundled binaries get re-installed via `SetupModel.installCLIIfNeeded()` on next launch. A fresh `brew install --cask joint-chiefs` (homebrew tap pending) achieves the same.
- **Build scripts:** `scripts/build-app.sh` (Release build + unsigned bundle assembly + Sparkle.framework copy + `install_name_tool` rpath patch), `scripts/build-dmg.sh` (unsigned development DMG creation), `scripts/generate-icon.sh` (icon `.icns` from PDF source). Release signing, notarization, stapling, and appcast updates are documented in `distribution/release-process.md`.

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial architecture |
| 1.1 | 2026-04-09 | Reflect current state: hub-and-spoke debate with Claude as moderator, SSE streaming via `URLSession.bytes`, HTTP server deferred, project structure trimmed to what actually exists, environment-variable configuration documented, 5 providers including Anthropic. |
| 1.2 | 2026-04-18 | v2 scope: added `jointchiefs-mcp` stdio server target, `jointchiefs-keygetter` as sole Keychain identity, `APIKeyResolver` as the env/keygetter funnel, `StrategyConfig` + `StrategyConfigStore` for moderator/consensus/rounds persistence. Removed the stale local-HTTP-server section. Security model updated for lean-baseline direction (Developer ID + notarization + Sparkle, no XPC, no custom updater). |
| 1.3 | 2026-04-19 | Added the `JointChiefsSetup` SwiftUI target (`jointchiefs-setup`) with Disclosure / Keys / Roles-&-Weights / Install / MCP-Config sections; the setup app goes through `APIKeyResolver.writeViaKeygetter` / `deleteViaKeygetter` rather than linking Keychain directly. Documented `StrategyConfig.providerWeights` and the weighted-voting path in `DebateOrchestrator.applyConsensusMode`. `ReviewProvider` now exposes `providerType` so the orchestrator can map a provider instance to its configured weight. |
| 1.4 | 2026-04-20 | Added website + repository references to the header, plus a new Distribution section documenting the Netlify deployment of jointchiefs.ai (site id, domain aliases, Sparkle appcast location). Corrected the auto-update description to match the lean baseline — Sparkle for the app bundle only, no custom updater for CLI/MCP binaries. |
| 1.5 | 2026-04-25 | Reconciled the Tech Stack and DebateOrchestrator sections with shipping reality — replaced the "Menu bar app, settings, transcript viewer" stack row with the four shipped surfaces (setup app, CLI, MCP server, keygetter); replaced "SwiftData persistence" with `StrategyConfig` JSON + local transcript files (SwiftData remains reserved for the deferred menu bar app). Bumped default debate rounds from 2 → 5 with adaptive early-break. Removed the "setup app is deferred" line above the project tree. Data-flow note flipped from "CLI or HTTP" to "CLI invocation or MCP tool call." |
| 1.6 | 2026-04-26 | Reconciled v0.4.0 + v0.5.0 changes that drifted from the doc. Added the 6th provider type (`openAICompatible` — LM Studio / Jan / llama.cpp-server / Msty / LocalAI) to the System Overview, ASCII diagram, project tree, streaming-providers list, and configuration env-var table. Rewrote the Setup App section: five sections are now Usage / Keys / Roles & Weights / MCP Config / Privacy (Install pane was replaced by silent auto-install in v0.3.0; "How to Use" is the new first screen; "Privacy" is the renamed Disclosure). Documented the v0.5.0 "Configured AI tools" panel and sidebar update-status footer with `MCPConfigScanner` and `UpdaterService`. Fixed the Development Environment dependencies line — removed Hummingbird and SwiftData (never landed / not used), listed the actual three deps from `Package.swift`. Distribution section reflects shipped state: notarized DMGs through v0.5.0, Sparkle appcast live, build-script trio (`build-app.sh`, `build-dmg.sh`, `generate-icon.sh`). |
| 1.7 | 2026-04-30 | Replaced the absurd "Full review (3 models, 2 rounds) < 90s" performance target. Realistic latency for a hub-and-spoke debate is minutes for cloud-only panels and 15+ minutes when a local model is in the panel — that's inference cost, not a hang. Added the three side channels for progress visibility (MCP `notifications/progress`, `jointchiefs-mcp` stderr heartbeats, and `~/Library/Caches/Joint Chiefs/current-review.json` status file) so a host UI showing only elapsed time doesn't make a working run look stuck. Source: tasks/lessons.md 2026-04-30 (`<90s` target retired) and the new `ProgressBroadcaster` in `JointChiefsMCPServer.swift`. |
| 1.8 | 2026-05-27 | Corrected provider lists and data-flow diagram to show all six provider surfaces plus moderator-led synthesis. Corrected Distribution to state that `build-app.sh` assembles an unsigned bundle; release signing/notarization lives in `distribution/release-process.md`. |
