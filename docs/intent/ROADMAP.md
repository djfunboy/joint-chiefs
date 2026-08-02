# Roadmap — Joint Chiefs

Durable intended sequence only. Current progress lives in
[`tasks/STATUS.md`](../../tasks/STATUS.md).

## Delivery prerequisites

- Build with Xcode 16 or newer and the macOS 15 SDK on Apple Silicon.
- Keep at least two LLM providers available for end-to-end debate validation.
- Keep the Swift package, provider protocol, and persisted configuration types fully typed.
- Keep the data model synchronized with the shipping configuration and credential stores.

## Phase 1 — Project scaffold and provider protocol

- Establish the Swift package and application lifecycle.
- Define the provider protocol and typed review models.
- Implement one provider end to end with mocked-network tests.

## Phase 2 — Provider panel

- Support OpenAI, Anthropic, Gemini, Grok, Ollama, and OpenAI-compatible local servers.
- Assemble configured providers dynamically and surface provider-specific failures.
- Stream every provider through SSE and cover each implementation with tests.

## Phase 3 — Debate orchestrator

- Run independent provider reviews in parallel.
- Feed anonymized findings through moderator-led debate rounds.
- Stop adaptively on convergence and synthesize one typed consensus.
- Persist the full transcript and degrade gracefully when a provider fails.

## Phase 4 — Local HTTP server

Keep this deferred unless a real cross-process use case emerges that stdio MCP and direct CLI invocation cannot serve. If revived, limit it to localhost review, status, and model endpoints with explicit lifecycle and integration tests. The stdio-only security decision is recorded in [`ADR-001`](./decisions/ADR-001-stdio-only-mcp.md).

## Phase 5 — CLI

- Provide file and stdin review flows with goal/context flags.
- Stream model and consensus output live.
- Return useful exit codes and configuration errors.
- Install a native `jointchiefs` executable for terminal and automation use.

## Phase 6 — Setup app

- Persist strategy, provider weights, model overrides, local-provider settings, and rate limits.
- Route every credential operation through the keygetter.
- Provide How to Use, API Keys, Roles & Weights, MCP Config, and Privacy sections.
- Validate keys, generate keyless MCP configuration, and detect configured MCP stanzas generically.
- Install the CLI, MCP server, and keygetter silently from the application bundle.
- Use Agentdeck tokens and components across every SwiftUI surface.
- Surface Sparkle update state without changing the one-shot setup model.
- Complete moderator-key preflight validation, VoiceOver validation, Dynamic Type validation, and the legacy-key migration smoke test.

## Phase 7 — Transcript viewer

Keep this deferred until browsing local transcript files becomes a demonstrated pain point. If revived, provide a searchable transcript list, round-by-round detail, consensus-first presentation, and deletion controls.

## Phase 8 — MCP server

- Expose `joint_chiefs_review` through the pinned Swift MCP SDK over stdio only.
- Share the same orchestrator, configuration, and credential-resolution path as the CLI.
- Enforce concurrency/hourly limits and cancel provider work when stdin closes.
- Keep setup guidance generic to any MCP-aware host.

## Phase 9 — Polish and testing

- Maintain orchestrator, consensus-mode, weighted-voting, credential-store, prompt-calibration, and resolver coverage.
- Complete VoiceOver and Dynamic Type verification across the setup app.
- Profile idle memory and full-review latency with cloud and local-model panels.
- Validate legacy-Keychain migration on a real upgrade and headless credential reads without a GUI session.
- Keep release-facing docs synchronized with shipping behavior.

## Phase 10 — Security and distribution

- Keep the public MIT repository and private website repository separate.
- Sign by certificate hash, notarize, staple, and verify every release artifact.
- Ship the setup app, CLI, MCP server, and keygetter through one notarized DMG.
- Deliver application updates through Sparkle and re-install bundled command-line binaries on launch.
- Preserve stdio-only MCP, redirect authorization stripping, rate limits, and the no-telemetry policy.
- Maintain the public security policy and the release runbook.

The accepted distribution baseline is recorded in [`ADR-003`](./decisions/ADR-003-standard-apple-distribution.md).

## Post-launch directions

- Publish the Homebrew cask through the intended tap.
- Evaluate additional providers such as Mistral and DeepSeek.
- Add automatic related-file, git-diff, and project-doc context only when it can remain predictable and bounded.
- Revisit shared configuration, transcript sync, and CI-gating only after demonstrated user demand.
