# Joint Chiefs — Data Model

**Version:** 1.0
**Last Updated:** 2026-04-08

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
