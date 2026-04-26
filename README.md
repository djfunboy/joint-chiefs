# Joint Chiefs

Multi-model AI code review. One command sends your code to OpenAI, Gemini, Grok, and Claude in parallel, runs a structured debate where they challenge each other's findings, and streams a single consensus summary back.

**Website:** [jointchiefs.ai](https://jointchiefs.ai/)

```
$ jointchiefs review src/auth.swift --goal "security audit"
```

## Why

Single-model code review has blind spots. GPT misses things Gemini catches; Gemini misses things Grok catches. Joint Chiefs runs them all, then has them argue.

The debate protocol is grounded in [Multi-Agent Debate research (Liang et al., 2023)](https://arxiv.org/abs/2305.19118), which shows that adversarial collaboration between LLMs produces more reliable output than any single model — including a single model reflecting on its own work.

## Surfaces

Joint Chiefs ships as three binaries, one engine:

| Binary | Use | How |
|---|---|---|
| `jointchiefs` | CLI for terminal, CI, scripting | `jointchiefs review <file>` |
| `jointchiefs-mcp` | MCP stdio server for any MCP-aware client | Paste the setup app's JSON snippet into your client's MCP config |
| `jointchiefs-setup` | One-shot SwiftUI installer (macOS) | Handles API key entry, strategy config, installs all three binaries |

A fourth binary, `jointchiefs-keygetter`, is the single signed identity allowed to read/write the Keychain. The CLI and MCP server call it via `Process`.

## Requirements

- **Apple Silicon Mac** (M-series). Intel Macs are not supported.
- macOS 15 (Sequoia) or later.
- Xcode 16+ with the macOS 15 SDK.
- API keys for at least one supported provider.

## Install

### From source

```bash
git clone https://github.com/djfunboy/joint-chiefs.git
cd joint-chiefs/JointChiefs
swift build -c release
cp .build/release/jointchiefs .build/release/jointchiefs-mcp .build/release/jointchiefs-keygetter /opt/homebrew/bin/
```

### API keys

Two paths:

**a) Environment variables** (CI-friendly):

```bash
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="..."
export GROK_API_KEY="..."
export ANTHROPIC_API_KEY="sk-ant-..."   # also acts as the moderator
```

**b) macOS Keychain** (end-user default, via the setup app):

Run `jointchiefs-setup`. It walks through disclosure, key entry (with live Test buttons), strategy config, install location, and outputs the MCP config snippet for your AI client.

You only need one key to get started. More keys = more diverse debate.

Verify:

```bash
jointchiefs models
```

## Usage

Review a file:

```bash
jointchiefs review src/auth.swift
```

With a directive to focus the panel:

```bash
jointchiefs review src/auth.swift --goal "look for race conditions in token refresh"
```

Pipe a diff in from stdin:

```bash
git diff main | jointchiefs review --stdin --goal "pre-commit check"
```

Quiet mode (suppress streaming, print only the final consensus):

```bash
jointchiefs review src/auth.swift --quiet
```

JSON output:

```bash
jointchiefs review src/auth.swift --format json
```

## MCP integration

The MCP server (`jointchiefs-mcp`) works with any MCP-aware client. The setup app's **MCP Config** tab emits a ready-to-paste `mcpServers` JSON snippet keyed at the installed binary path. No keys live in the snippet — Joint Chiefs resolves them from the Keychain at tool-call time.

Minimal snippet shape:

```json
{
  "mcpServers": {
    "joint-chiefs": {
      "command": "/opt/homebrew/bin/jointchiefs-mcp"
    }
  }
}
```

## How it works

```
                  ┌──────────────────────┐
                  │  DebateOrchestrator  │
                  └──────────┬───────────┘
                             │
       ┌──────────┬──────────┼──────────┬──────────┐
       ▼          ▼          ▼          ▼          ▼
   ┌────────┐┌──────────┐┌────────┐┌────────┐┌─────────┐
   │ OpenAI ││Anthropic ││ Gemini ││  Grok  ││  local  │   parallel review
   └────┬───┘└────┬─────┘└───┬────┘└───┬────┘└────┬────┘   (Ollama / LM Studio
        └────────┴──────────┼──────────┴──────────┘         / any OpenAI-compat)
                            │  anonymized findings
                            ▼
                  ┌────────────────────┐
                  │      Moderator     │   synthesizes round, writes brief
                  │  (default: Claude) │
                  └─────────┬──────────┘
                            │
                            ▼
             Next round, or — if positions converged —
             the moderator writes the final consensus.
```

You pick which providers participate. The moderator is configurable too (default: Claude); the same provider can serve as both a spoke and the moderator if you want, or you can split the roles.

Up to 5 debate rounds with adaptive early break when positions converge. Findings are anonymized before the final synthesis to reduce bias toward any single provider. Four consensus modes (`moderatorDecides`, `strictMajority`, `bestOfAll`, `votingThreshold`) with per-provider weighting.

Full details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| `OPENAI_API_KEY` | OpenAI authentication | (required to enable OpenAI) |
| `OPENAI_MODEL` | OpenAI model override | `gpt-5.4` |
| `GEMINI_API_KEY` | Google Gemini authentication | (required to enable Gemini) |
| `GEMINI_MODEL` | Gemini model override | `gemini-3.1-pro-preview` |
| `GROK_API_KEY` | xAI Grok authentication | (required to enable Grok) |
| `GROK_MODEL` | Grok model override | `grok-3` |
| `ANTHROPIC_API_KEY` | Anthropic — also serves as moderator | (required to enable Claude) |
| `ANTHROPIC_MODEL` | Claude model override | `claude-opus-4-6` |
| `OLLAMA_ENABLED` | Set to `1` to force-include / `0` to force-exclude the local Ollama general (overrides `StrategyConfig.ollama.enabled`) | unset (use `StrategyConfig`) |
| `OLLAMA_MODEL` | Ollama model override | `llama3` |
| `OPENAI_COMPATIBLE_BASE_URL` | Force-enable an OpenAI-compatible local server (LM Studio, Jan, llama.cpp-server, Msty, LocalAI). CI override for `StrategyConfig.openAICompatible`. | unset |
| `OPENAI_COMPATIBLE_MODEL` | Model identifier as the local server exposes it | unset |
| `CONSENSUS_MODEL` | Override the Claude model used for the final synthesis | falls back to `ANTHROPIC_MODEL` |

CLI flags:

| Flag | Purpose | Default |
|---|---|---|
| `--goal "..."` | Directive to the panel | (none) |
| `--context "..."` | Free-form additional context | (none) |
| `--rounds N` | Max debate rounds | `5` |
| `--timeout N` | Per-provider timeout in seconds | `120` |
| `--format` | `summary`, `json`, or `full` | `summary` |
| `--quiet` | Suppress streaming, only show final result | off |
| `--stdin` | Read code from standard input | off |

## Privacy

- API keys live in the macOS Keychain, reachable only via the signed `jointchiefs-keygetter` binary. Env vars exist as a CI fallback.
- No telemetry. No analytics. The only network traffic is to the LLM APIs you've configured.
- The MCP server is **stdio-only** — nothing binds a port.
- Code sent for review is stored only in local transcript files. Delete them whenever.

## Development

```bash
cd JointChiefs
swift test          # 80 tests
swift build -c release
```

The project layout:

```
JointChiefs/
├── Package.swift
├── Sources/
│   ├── JointChiefsCore/        # Models, providers, orchestrator, APIKeyResolver
│   ├── JointChiefsCLI/         # jointchiefs executable
│   ├── JointChiefsMCP/         # jointchiefs-mcp stdio server
│   ├── JointChiefsSetup/       # jointchiefs-setup SwiftUI installer
│   └── JointChiefsKeygetter/   # jointchiefs-keygetter — sole Keychain identity
└── Tests/JointChiefsCoreTests/
```

## Contributing

PRs welcome — especially first-class providers for Mistral and DeepSeek. Both are reachable today via the OpenAI-compatible path (point `OPENAI_COMPATIBLE_BASE_URL` at `https://api.mistral.ai/v1` or `https://api.deepseek.com/v1`); native providers would add curated model lists and provider-specific handling. This is a solo-maintained project, so response times will vary. No SLA, no promises about backwards compatibility, and breaking changes can land on `main` between releases.

If you want to add a provider, conform to the `ReviewProvider` protocol in [`Sources/JointChiefsCore/Services/Providers/ReviewProvider.swift`](JointChiefs/Sources/JointChiefsCore/Services/Providers/ReviewProvider.swift) and use SSE streaming end-to-end — non-streaming LLM calls are not accepted.

## License

MIT — see [`LICENSE`](LICENSE).
