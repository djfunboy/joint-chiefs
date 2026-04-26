# Joint Chiefs — Data Model

**Version:** 1.2
**Last Updated:** 2026-04-26

## Live Configuration Types

These types are the ones actually in the shipping codebase. The SwiftData schema
later in this document describes the deferred menu bar app and should be read as
a future-direction reference, not a description of runtime state today.

### StrategyConfig

Persisted at `~/Library/Application Support/Joint Chiefs/strategy.json` via
`StrategyConfigStore`. Read by the CLI, MCP server, and setup app; written
only by the setup app.

```swift
public struct StrategyConfig: Codable, Sendable, Equatable {
    public var moderator: ModeratorSelection            // .claude, .openai, .gemini, .grok, .none
    public var tiebreaker: TiebreakerSelection          // .sameAsModerator | .specific(ModeratorSelection)
    public var consensus: ConsensusMode                 // .moderatorDecides, .strictMajority, .bestOfAll, .votingThreshold
    public var maxRounds: Int                           // default 5 (adaptive early-break inside)
    public var timeoutSeconds: Int                      // default 120
    public var thresholdPercent: Double                 // 0.0–1.0; only used by .votingThreshold
    public var providerWeights: [ProviderType: Double]  // 0 = excluded, 1.0 = default, >1 = heavier vote
    public var providerModels: [ProviderType: String]   // per-provider model override; resolution priority providerModels > env var > defaultModel
    public var ollama: OllamaConfig                     // local Ollama server config (enabled, baseURL, model)
    public var openAICompatible: OpenAICompatibleConfig // local OpenAI-compatible server (LM Studio / Jan / llama.cpp-server / Msty / LocalAI)
    public var rateLimits: RateLimits                   // MCP-only: maxConcurrentReviews, reviewsPerHour, dailySpendCapUSD?
}
```

### providerWeights

Semantics:

- Missing entries default to `1.0`.
- A weight of `0.0` (or any non-positive value) excludes the provider from the
  spoke panel at `ProviderFactory.buildPanel` time, even if an API key is
  available.
- Non-zero weights drive voting-threshold math: the survival ratio is
  `sum(weights of providers who raised the finding) / sum(weights of providers
  that responded in the final round)`.

On-disk JSON form is a readable object, not the Swift default flat-array:

```json
{
  "providerWeights": {
    "openAI": 1.5,
    "gemini": 0.0,
    "grok": 1.0,
    "anthropic": 2.0
  }
}
```

Older `strategy.json` files that predate the field decode to `[:]` via
`decodeIfPresent`, so upgrades are silent.

### providerModels

Per-provider model override. Resolution priority in `ProviderFactory`:
`providerModels[type]` > env var (`OPENAI_MODEL`, `ANTHROPIC_MODEL`,
`GEMINI_MODEL`, `GROK_MODEL`, `OLLAMA_MODEL`, `OPENAI_COMPATIBLE_MODEL`) >
`ProviderType.defaultModel`. Empty-string entries are treated as missing so
users can't accidentally lock a provider into a blank model.

The setup app's KeysView surfaces a curated top-5 picker per provider via
`ProviderType.availableModels` — first entry always matches `defaultModel`.
Users who need a model outside the curated list can still override via env
var.

```json
{
  "providerModels": {
    "openAI": "gpt-5.4-mini",
    "anthropic": "claude-sonnet-4-6"
  }
}
```

### ollama

Configuration for the optional local Ollama general. When `enabled` is false,
Ollama is skipped even if the server is reachable. The `OLLAMA_ENABLED` env
var remains a CI override: set to `1` to force-include or `0` to force-exclude,
regardless of this setting.

```swift
public struct OllamaConfig: Codable, Sendable, Equatable {
    public var enabled: Bool        // default false
    public var baseURL: String      // default http://localhost:11434
    public var model: String        // default "llama3"
}
```

### openAICompatible

Configuration for an optional local inference server that speaks the OpenAI
chat-completions protocol. Covers LM Studio, Jan, llama.cpp-server, Msty,
LocalAI, and anything else compatible with `/v1/chat/completions`. Sits
alongside (not instead of) `ollama` — some users run both, and Ollama's
native protocol carries richer model-state signals worth preserving. The
`OPENAI_COMPATIBLE_BASE_URL` env var is the CI override for headless runs.

```swift
public struct OpenAICompatibleConfig: Codable, Sendable, Equatable {
    public var enabled: Bool        // default false
    public var baseURL: String      // default http://localhost:1234/v1 (LM Studio default)
    public var model: String        // whatever the local server exposes; "" until set
    public var presetName: String   // display-only hint for the setup app UI ("LM Studio", "Jan", etc.)
}
```

### ProviderType

```swift
public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case openAI, anthropic, gemini, grok, ollama, openAICompatible

    public var envVarName: String              // CI-only fallback
    public var keychainAccount: String?        // nil for Ollama and openAICompatible (no credential)
    public var defaultModel: String
    public var defaultEndpoint: String
    public var availableModels: [String]       // curated top-5 for the KeysView picker (empty for local providers)
}
```

Every concrete `ReviewProvider` exposes a `providerType` property so the
orchestrator can map a provider instance back to its `StrategyConfig` weight
without string matching.

---

## Schema Overview (deferred menu bar app)

> The rest of this document describes SwiftData models designed for the deferred
> menu bar app (PRD F5/F7). Nothing below is live today — review transcripts
> ship as Codable value types, settings as `StrategyConfig` above, and API keys
> through the Keychain via the keygetter.

## Schema Overview

```
┌─────────────────┐     ┌──────────────────┐
│ ProviderConfig   │     │ ReviewSettings    │
│─────────────────│     │──────────────────│
│ name            │     │ debateRounds     │
│ providerType    │     │ timeoutSeconds   │
│ model           │     │ defaultGoal      │
│ endpoint        │     │ severityThreshold│
│ isEnabled       │     │ serverPort       │
│ sortOrder       │     │ launchAtLogin    │
│ keychainID      │     └──────────────────┘
└─────────────────┘
         │ consulted by
         ▼
┌──────────────────┐     ┌──────────────────┐
│ DebateTranscript  │────▶│ TranscriptRound   │
│──────────────────│     │──────────────────│
│ id              │     │ roundNumber      │
│ createdAt       │     │ phase            │
│ filePath        │     │ responses        │
│ goal            │     └──────────────────┘
│ codeSnippet     │              │
│ consensusSummary│              ▼
│ modelsConsulted │     ┌──────────────────┐
│ roundsCompleted │     │ ModelResponse     │
│ status          │     │──────────────────│
└──────────────────┘     │ providerName    │
                         │ model           │
                         │ content         │
                         │ findings        │
                         │ timestamp       │
                         └──────────────────┘
                                  │
                                  ▼
                         ┌──────────────────┐
                         │ Finding           │
                         │──────────────────│
                         │ title            │
                         │ description      │
                         │ severity         │
                         │ agreement        │
                         │ recommendation   │
                         │ location         │
                         └──────────────────┘
```

## SwiftData Model Definitions

### ProviderConfig

```swift
@Model
final class ProviderConfig {
    var name: String
    var providerType: ProviderType
    var model: String
    var endpoint: String
    var isEnabled: Bool
    var sortOrder: Int
    var keychainID: String  // Reference to Keychain item for API key
    var createdAt: Date

    init(name: String, providerType: ProviderType, model: String, endpoint: String) {
        self.name = name
        self.providerType = providerType
        self.model = model
        self.endpoint = endpoint
        self.isEnabled = true
        self.sortOrder = 0
        self.keychainID = UUID().uuidString
        self.createdAt = .now
    }
}
```

### ProviderType

```swift
enum ProviderType: String, Codable, CaseIterable {
    case openAI
    case gemini
    case grok
    case ollama

    var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .grok: "https://api.x.ai/v1"
        case .ollama: "http://localhost:11434"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5"
        case .gemini: "gemini-3-pro"
        case .grok: "grok-3"
        case .ollama: "llama3"
        }
    }
}
```

### ReviewSettings

```swift
@Model
final class ReviewSettings {
    var debateRounds: Int
    var timeoutSeconds: Int
    var defaultGoal: String
    var severityThreshold: Severity
    var serverPort: Int
    var launchAtLogin: Bool

    init() {
        self.debateRounds = 2
        self.timeoutSeconds = 60
        self.defaultGoal = ""
        self.severityThreshold = .low
        self.serverPort = 7777
        self.launchAtLogin = false
    }
}
```

### DebateTranscript

```swift
@Model
final class DebateTranscript {
    var id: UUID
    var createdAt: Date
    var filePath: String
    var goal: String
    var codeSnippet: String
    var consensusSummary: String
    var modelsConsulted: [String]
    var roundsCompleted: Int
    var status: ReviewStatus
    @Relationship(deleteRule: .cascade) var rounds: [TranscriptRound]

    init(filePath: String, goal: String, codeSnippet: String) {
        self.id = UUID()
        self.createdAt = .now
        self.filePath = filePath
        self.goal = goal
        self.codeSnippet = codeSnippet
        self.consensusSummary = ""
        self.modelsConsulted = []
        self.roundsCompleted = 0
        self.status = .inProgress
        self.rounds = []
    }
}
```

### TranscriptRound

```swift
@Model
final class TranscriptRound {
    var roundNumber: Int
    var phase: ReviewPhase
    @Relationship(deleteRule: .cascade) var responses: [ModelResponse]

    init(roundNumber: Int, phase: ReviewPhase) {
        self.roundNumber = roundNumber
        self.phase = phase
        self.responses = []
    }
}
```

### ModelResponse

```swift
@Model
final class ModelResponse {
    var providerName: String
    var model: String
    var content: String
    var findings: [Finding]
    var timestamp: Date

    init(providerName: String, model: String, content: String, findings: [Finding]) {
        self.providerName = providerName
        self.model = model
        self.content = content
        self.findings = findings
        self.timestamp = .now
    }
}
```

### Finding

```swift
struct Finding: Codable, Hashable {
    var title: String
    var description: String
    var severity: Severity
    var agreement: AgreementLevel
    var recommendation: String
    var location: String  // e.g., "line 42" or "authenticate() function"
}
```

### Enums

```swift
enum Severity: String, Codable, CaseIterable, Comparable {
    case critical
    case high
    case medium
    case low

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        let order: [Severity] = [.low, .medium, .high, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

enum AgreementLevel: String, Codable {
    case unanimous    // All models agree
    case majority     // Most models agree
    case split        // No clear majority
    case solo         // Only one model raised this
}

enum ReviewPhase: String, Codable {
    case independent  // Initial parallel review
    case debate       // Challenge round
    case consensus    // Final synthesis
}

enum ReviewStatus: String, Codable {
    case inProgress
    case completed
    case failed
}
```

## Keychain Storage

API keys are NOT stored in SwiftData. Each `ProviderConfig` has a `keychainID` string that references a Keychain item:

```swift
// Store
KeychainService.store(apiKey: "sk-...", for: config.keychainID)

// Retrieve
let apiKey = try KeychainService.retrieve(for: config.keychainID)

// Delete (when provider is removed)
KeychainService.delete(for: config.keychainID)
```

Keychain items use:
- Service: `"com.jointchiefs.provider"`
- Account: `keychainID` from the `ProviderConfig`

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial data model |
| 1.1 | 2026-04-19 | Added "Live Configuration Types" section describing `StrategyConfig` (including `providerWeights`) and `ProviderType` as they actually exist in the shipping codebase. Marked the SwiftData section as deferred-menu-bar-app reference material. |
| 1.2 | 2026-04-26 | Reconciled `StrategyConfig` with shipping fields the v1.1 doc was missing: `providerModels` (per-provider model override; v0.3.0), `ollama: OllamaConfig` (first-class config; v0.3.0+), `openAICompatible: OpenAICompatibleConfig` (LM Studio / Jan / llama.cpp-server / Msty / LocalAI; v0.4.0). Added the `.openAICompatible` case to the live `ProviderType` enum and documented `availableModels` (curated top-5 picker source). Added new sections describing `providerModels`, `ollama`, and `openAICompatible` semantics + on-disk JSON shape. |
