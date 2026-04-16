# Joint Chiefs

Multi-model AI code review from your terminal. One command sends your code to OpenAI, Gemini, Grok, and Claude in parallel, runs a structured debate where they challenge each other's findings, and streams a single consensus summary back.

```
$ jointchiefs review src/auth.swift --goal "security audit"
```

## Why

Single-model code review has blind spots. GPT misses things Gemini catches; Gemini misses things Grok catches. Joint Chiefs runs them all, then has them argue.

The debate protocol is grounded in [Multi-Agent Debate research (Liang et al., 2023)](https://arxiv.org/abs/2305.19118), which shows that adversarial collaboration between LLMs produces more reliable output than any single model — including a single model reflecting on its own work.

## Requirements

- **Apple Silicon Mac** (M-series). Intel Macs are not supported.
- macOS 15 (Sequoia) or later.
- Xcode 16+ with the macOS 15 SDK.
- API keys for at least one supported provider.

## Install

```bash
git clone https://github.com/<your-fork>/joint-chiefs.git
cd joint-chiefs/JointChiefs
swift build -c release
cp .build/release/jointchiefs /opt/homebrew/bin/jointchiefs
```

Add API keys to your shell profile (`~/.zshrc`):

```bash
export OPENAI_API_KEY="sk-..."
export GEMINI_API_KEY="..."
export GROK_API_KEY="..."
export ANTHROPIC_API_KEY="sk-ant-..."   # also acts as the moderator
```

You only need one key to get started. More keys = more diverse debate.

Verify the install:

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

## How it works

```
                  ┌──────────────────────┐
                  │  DebateOrchestrator  │
                  └──────────┬───────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   ┌────────┐          ┌──────────┐         ┌────────┐
   │ OpenAI │          │  Gemini  │         │  Grok  │   parallel review
   └────┬───┘          └────┬─────┘         └────┬───┘
        └────────────┬──────┴────────────────────┘
                     │  anonymized findings
                     ▼
            ┌──────────────────┐
            │ Claude moderates │   synthesizes round, writes brief
            └────────┬─────────┘
                     │
                     ▼
       Next round, or — if positions converged —
       Claude writes the final consensus summary.
```

Up to 5 debate rounds with adaptive early break when positions converge. Findings are anonymized before the final synthesis to reduce bias toward any single provider.

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
| `OLLAMA_ENABLED` | Set to `1` to include local Ollama models | off |
| `OLLAMA_MODEL` | Ollama model override | `llama3` |
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

- API keys live in environment variables (or macOS Keychain via `KeychainService`). Never written to disk in plaintext by Joint Chiefs.
- No telemetry. No analytics. The only network traffic is to the LLM APIs you've configured.
- Code sent for review is stored only in local transcript files. Delete them whenever.

## Development

```bash
cd JointChiefs
swift test          # 41 tests
swift build -c release
```

The project layout:

```
JointChiefs/
├── Sources/
│   ├── JointChiefsCore/    # Models, providers, orchestrator
│   └── JointChiefsCLI/     # `jointchiefs` executable
└── Tests/JointChiefsCoreTests/
```

## Contributing

PRs welcome — especially for new providers (Mistral and DeepSeek are on the roadmap). This is a solo-maintained project, so response times will vary. No SLA, no promises about backwards compatibility, and breaking changes can land on `main` between releases.

If you want to add a provider, conform to the `ReviewProvider` protocol in [`Sources/JointChiefsCore/Services/Providers/ReviewProvider.swift`](JointChiefs/Sources/JointChiefsCore/Services/Providers/ReviewProvider.swift) and use SSE streaming end-to-end — non-streaming LLM calls are not accepted.

## License

MIT — see [`LICENSE`](LICENSE).
