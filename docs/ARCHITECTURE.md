# Joint Chiefs — Architecture

**Version:** 1.4
**Last Updated:** 2026-04-20

**Website:** [jointchiefs.ai](https://jointchiefs.ai/) — deployed via Netlify. Source in the private `djfunboy/joint-chiefs-website` repo.
**App repo:** [github.com/djfunboy/joint-chiefs](https://github.com/djfunboy/joint-chiefs) (public, MIT).

## System Overview

Joint Chiefs uses a **hub-and-spoke** debate model. The "generals" (OpenAI,
Gemini, Grok, Ollama) each review the code independently and send their
findings to Claude, who acts as the moderator/hub. Claude synthesizes the
round's findings, sends the anonymized synthesis back to the generals for
the next round, and — once consensus is reached or max rounds hit — writes
the final summary. A code-based `ConsensusBuilder` is available as a
fallback if Claude is unavailable.

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
  ┌──────────────────────────────────────────┐
  │  Generals (independent, parallel review) │
  │                                          │
  │  ┌──────┐ ┌──────┐ ┌────┐ ┌──────┐       │
  │  │OpenAI│ │Gemini│ │Grok│ │Ollama│       │
  │  └──┬───┘ └──┬───┘ └─┬──┘ └──┬───┘       │
  └─────┼────────┼───────┼───────┼───────────┘
        │        │       │       │
        └────────┴───┬───┴───────┘
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
| App framework | SwiftUI | Menu bar app, settings, transcript viewer |
| HTTP server | Deferred — CLI direct call works for solo use | No local server needed today |
| CLI | Swift ArgumentParser | `jointchiefs` command-line tool |
| Persistence | SwiftData | Settings, transcripts, provider configs |
| Secrets | macOS Keychain | API key storage |
| Networking | URLSession | LLM API calls |
| API Calls | URLSession.bytes (SSE streaming) | Stream LLM responses, no timeouts |
| MCP (optional) | stdio wrapper | Native integration with any MCP client |
| Minimum target | macOS 15 | @Observable, SwiftData |

## Project Structure

Only what currently exists in the repo. The setup app is deferred.

```
JointChiefs/
├── Package.swift
├── Sources/
│   ├── JointChiefsCore/
│   │   ├── Models/
│   │   │   └── StrategyConfig.swift         (moderator/tiebreaker/consensus/rounds/timeout/providerWeights)
│   │   ├── Errors/
│   │   └── Services/
│   │       ├── APIKeyResolver.swift         (env → keygetter; read/write/delete; CLI + MCP + setup app funnel through it)
│   │       ├── KeychainService.swift        (used *only* by the keygetter binary)
│   │       ├── StrategyConfigStore.swift    (load/save ~/Library/Application Support/…)
│   │       ├── ProviderFactory.swift        (panel assembly; filters `weight == 0`; moderator/tiebreaker builders)
│   │       ├── ConsensusBuilder.swift
│   │       ├── DebateOrchestrator.swift
│   │       └── Providers/  (OpenAI, Gemini, Grok, Anthropic, Ollama — each exposes providerType)
│   ├── JointChiefsCLI/                       (executable: jointchiefs)
│   ├── JointChiefsMCP/                       (executable: jointchiefs-mcp — stdio only)
│   ├── JointChiefsKeygetter/                 (executable: jointchiefs-keygetter)
│   └── JointChiefsSetup/                     (executable: jointchiefs-setup — SwiftUI one-shot installer)
│       ├── SetupApp.swift                   (@main, AppKit delegate for foreground activation)
│       ├── Model/SetupModel.swift           (@Observable @MainActor state; probes Keychain on launch)
│       └── Views/                           (DisclosureView, KeysView, RolesWeightsView, InstallView, MCPConfigView)
└── Tests/JointChiefsCoreTests/
```

## Key Components

### ReviewProvider Protocol

```swift
protocol ReviewProvider: Sendable {
    var name: String { get }
    var model: String { get }
    func review(code: String, context: ReviewContext) async throws -> ProviderReview
    func debate(code: String, priorFindings: [Finding], round: Int) async throws -> ProviderReview
    func testConnection() async throws -> Bool
}
```

All providers conform to this protocol. Each provider:
- Wraps a single LLM API (OpenAI, Gemini, xAI, Ollama)
- Handles its own authentication and request formatting
- Returns a structured `ProviderReview` with typed findings

### DebateOrchestrator

The core engine. Manages the full review lifecycle:

1. **Parallel Review Phase:** Sends code to all configured providers simultaneously via `TaskGroup`. Each returns independent findings.
2. **Debate Rounds:** For each round (configurable, default 2):
   - Sends all prior findings to each provider
   - Each provider can agree, disagree, revise, or raise new findings
   - Tracks position changes across rounds
3. **Consensus Phase:** Passes all findings + debate history to `ConsensusBuilder`, which produces the final `ConsensusSummary`.
4. **Storage:** Saves full `DebateTranscript` to SwiftData. Returns only `ConsensusSummary` to caller.

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
without requiring shell surgery. Five sections, navigable via a sidebar:

- **Data Handling** — first-run disclosure: what's sent to providers, what
  stays local, what the app refuses to do (no telemetry, no analytics).
- **API Keys** — masked entry per provider. Save writes to the Keychain via
  `APIKeyResolver.writeViaKeygetter`; Test resolves the key and runs
  `ReviewProvider.testConnection()`; Delete calls
  `APIKeyResolver.deleteViaKeygetter`. Ollama is shown read-only.
- **Roles & Weights** — moderator picker, tiebreaker picker, consensus-mode
  picker, rounds and timeout sliders, per-provider weight sliders (0 = excluded
  from panel, 1.0 = default vote, up to 3.0 = triple vote). Dirty-state
  indicator plus an explicit Save action persisting to
  `StrategyConfigStore.save(_:)`.
- **Install** — destination picker (Homebrew prefix if writable, `~/.local/bin`
  fallback, custom via `NSOpenPanel`), PATH detection, and a button that copies
  `jointchiefs`, `jointchiefs-mcp`, and `jointchiefs-keygetter` into the chosen
  directory with `0o755` perms.
- **MCP Config** — generates a standard `mcpServers` JSON snippet that points
  at the installed `jointchiefs-mcp` path. Works with any MCP client. No key
  material in the snippet — keys live in the Keychain, resolved at tool-call
  time.

The setup app talks to the Keychain *only* through the keygetter for the same
reason the CLI and MCP server do — see the keygetter section below. It does
not link against `Security.framework` directly.

### APIKeyResolver and `jointchiefs-keygetter`

Instead of embedding Keychain access in every binary, only one signed binary
(`jointchiefs-keygetter`) is permitted to touch Joint Chiefs' Keychain items.
The CLI and MCP server invoke it via `Process` and read the key from stdout.
This was validated empirically in `prototypes/keychain-access/` — a single
trusted identity avoids cross-binary ACL churn when any of the surfaces is
updated in place.

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
| 2 | Keychain encode/decode failure |
| 3 | Item not found (resolver returns nil, not an error) |
| 4 | Interaction required (headless failure — throws) |
| 5 | Other keychain error |
| 64 | Usage error |

## Data Flow

```
1. Request arrives (CLI or HTTP)
         │
2. DebateOrchestrator.startReview()
         │
3. ┌─────┼─────┐─────┐
   │     │     │     │     Parallel: independent reviews
   ▼     ▼     ▼     ▼
  GPT  Gemini Grok  Ollama
   │     │     │     │
   └─────┼─────┘─────┘
         │
4. Collect findings, build round 1 context
         │
5. ┌─────┼─────┐─────┐
   │     │     │     │     Debate round 1: challenge findings
   ▼     ▼     ▼     ▼
  GPT  Gemini Grok  Ollama
   │     │     │     │
   └─────┼─────┘─────┘
         │
6. Repeat for configured rounds
         │
7. ConsensusBuilder.synthesize()
         │
   ┌─────┴──────┐
   │             │
   ▼             ▼
Summary      Transcript
(returned)   (stored in SwiftData)
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
- **Consistent across providers.** OpenAI, Gemini, Grok, Anthropic, and
  Ollama all stream through the same `AsyncStream<ReviewChunk>` shape,
  so the orchestrator doesn't need provider-specific buffering logic.

## Configuration

Provider API keys are resolved via `APIKeyResolver` (env var → keygetter). The
env var is a CI-only escape hatch; end users add keys via the setup app, which
writes them to the Keychain through the keygetter.

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
| `OPENAI_MODEL` | OpenAI model override | `gpt-5.4` |
| `GEMINI_API_KEY` | Google Gemini authentication | (required to enable Gemini) |
| `GEMINI_MODEL` | Gemini model override | `gemini-3.1-pro-preview` |
| `GROK_API_KEY` | xAI Grok authentication | (required to enable Grok) |
| `GROK_MODEL` | Grok model override | `grok-3` |
| `ANTHROPIC_API_KEY` | Anthropic authentication — also serves as deciding model | (required to enable Claude) |
| `ANTHROPIC_MODEL` | Claude model override | `claude-opus-4-6` |
| `OLLAMA_ENABLED` | Set to `1` to include local Ollama models | off |
| `OLLAMA_MODEL` | Ollama model override | `llama3` |
| `CONSENSUS_MODEL` | Override the Claude model used for consensus synthesis | falls back to `ANTHROPIC_MODEL` |

Claude (via `ANTHROPIC_API_KEY`) plays a dual role: it reviews code as one
of the generals and also acts as the moderator/decider for the final
synthesis. `CONSENSUS_MODEL` lets you split these — e.g. use a smaller
Claude model for per-round reviews and a larger one for the final call.

## Security Model

- **API keys** live in the macOS Keychain, accessed exclusively by a single
  signed binary (`jointchiefs-keygetter`). The CLI and MCP server invoke it
  via `Process` and drop the key immediately after use — see the
  `APIKeyResolver` and keygetter sections above.
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

| Metric | Target |
|---|---|
| Request to first API call | < 2s |
| Full review (3 models, 2 rounds) | < 90s |
| App idle memory | < 100MB |
| Server overhead per request | < 100ms |
| Transcript storage per review | < 500KB |

## Development Environment

- **Xcode 16+** with Swift 6
- **macOS 15+** for development and deployment
- **Swift Package Manager** for dependencies
- **Dependencies:** Hummingbird, Swift ArgumentParser, SwiftData (system)

## Distribution

- **App repo:** public at [github.com/djfunboy/joint-chiefs](https://github.com/djfunboy/joint-chiefs) — MIT licensed.
- **Website:** [jointchiefs.ai](https://jointchiefs.ai/) — static HTML + shared `styles.css`, Agentdeck palette matching the setup app. Hosted on Netlify (site ID `79794bf5-ed42-41bb-9610-a6cd57a79a12`); source is a separate private repo (`djfunboy/joint-chiefs-website`). Netlify manages the apex domain + `www` alias + Let's Encrypt cert.
- **Release artifact** (pending): notarized DMG containing `Joint Chiefs.app`. The Sparkle appcast feed lives at `jointchiefs.ai/appcast.xml` (placeholder until first notarized release).
- **Auto-update path:** Sparkle for the app bundle. No custom updater for the CLI or MCP binaries — a fresh `brew install` (once the tap is live) or a re-run of the setup app picks up new versions.

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial architecture |
| 1.1 | 2026-04-09 | Reflect current state: hub-and-spoke debate with Claude as moderator, SSE streaming via `URLSession.bytes`, HTTP server deferred, project structure trimmed to what actually exists, environment-variable configuration documented, 5 providers including Anthropic. |
| 1.2 | 2026-04-18 | v2 scope: added `jointchiefs-mcp` stdio server target, `jointchiefs-keygetter` as sole Keychain identity, `APIKeyResolver` as the env/keygetter funnel, `StrategyConfig` + `StrategyConfigStore` for moderator/consensus/rounds persistence. Removed the stale local-HTTP-server section. Security model updated for lean-baseline direction (Developer ID + notarization + Sparkle, no XPC, no custom updater). |
| 1.3 | 2026-04-19 | Added the `JointChiefsSetup` SwiftUI target (`jointchiefs-setup`) with Disclosure / Keys / Roles-&-Weights / Install / MCP-Config sections; the setup app goes through `APIKeyResolver.writeViaKeygetter` / `deleteViaKeygetter` rather than linking Keychain directly. Documented `StrategyConfig.providerWeights` and the weighted-voting path in `DebateOrchestrator.applyConsensusMode`. `ReviewProvider` now exposes `providerType` so the orchestrator can map a provider instance to its configured weight. |
| 1.4 | 2026-04-20 | Added website + repository references to the header, plus a new Distribution section documenting the Netlify deployment of jointchiefs.ai (site id, domain aliases, Sparkle appcast location). Corrected the auto-update description to match the lean baseline — Sparkle for the app bundle only, no custom updater for CLI/MCP binaries. |
