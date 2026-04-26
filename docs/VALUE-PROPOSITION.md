# Joint Chiefs — Value Proposition

**Version:** 2.2
**Last Updated:** 2026-04-26

**Website:** [jointchiefs.ai](https://jointchiefs.ai/) (live)
**Repo:** [github.com/djfunboy/joint-chiefs](https://github.com/djfunboy/joint-chiefs) (public, MIT)

## Core Value Proposition

**An MCP server for multi-model code review — with structured debate, not just a vote.**

Joint Chiefs is an MCP server that runs your code past OpenAI, Anthropic, Gemini, and Grok in parallel — plus any local model you point it at via Ollama or an OpenAI-compatible server (LM Studio, Jan, llama.cpp-server, Msty, LocalAI) — then makes them argue. Findings are challenged across multiple debate rounds until positions converge, then a moderator model writes a single anonymized consensus summary. The protocol is grounded in Multi-Agent Debate (MAD) research (Liang et al., 2023, [arXiv:2305.19118](https://arxiv.org/abs/2305.19118)), which shows adversarial collaboration between LLMs beats both single-model inference and single-model self-reflection on factuality and reasoning.

Ships as three user-facing surfaces plus one trust-anchor binary, one project:

- **MCP server** (`jointchiefs-mcp`) — the primary integration. Drop it into any MCP-aware client. The host LLM calls `joint_chiefs_review` and gets back a consensus.
- **CLI** (`jointchiefs`) — for setup, debugging, headless use, and CI pipelines. Same engine, scriptable.
- **macOS setup app** (`jointchiefs-setup`) — one-shot installer GUI. Five sections: How to Use, API Keys (with live test buttons + curated model picker), Roles & Weights, MCP Config (with a "Configured AI tools" panel that scans your home dir for MCP-aware clients), and Privacy. CLI binaries install silently on first launch.
- **Keygetter** (`jointchiefs-keygetter`) — the only signed binary allowed to read/write Joint Chiefs' Keychain items. The other three call it via `Process`. You'll never run it directly; it exists to keep your API keys behind a single ACL boundary.

## Problem Statement

The MCP ecosystem in 2026 is saturated with single-model second-opinion servers and "ask another model" tools. They have real shortcomings:

- **Single-perspective second opinions.** Most "second opinion" MCP servers route to one external model. That swaps one bias for another — it doesn't reduce blind spots.
- **Vote-based consensus.** A few servers (Zen MCP, multi_mcp) consult multiple models in parallel, but treat the result as a poll. Majority wins, well-reasoned minority positions get buried.
- **Self-reflection masquerading as review.** Asking a coding LLM to review its own diff suffers from Degeneration of Thought — the central problem the MAD paper identifies. Confidence increases regardless of correctness.
- **Setup friction.** API keys for four providers, MCP JSON snippets that vary per client, binaries to compile and install — most developers bounce before they've issued a single review.

Joint Chiefs is the answer to all four.

## Target Audience

### Primary: Developers Using AI-Native Coding Tools
You're in an MCP-capable client every day. You already have API keys for two or more providers. You want higher-confidence review than your daily driver model can give itself, without leaving the chat.

### Secondary: Solo Developers and Small Teams in CI
You want the same multi-model debate to gate pre-commit hooks, PR checks, or release builds. The CLI runs headless with JSON output and exit codes.

### Tertiary: Researchers and Power Users
You care about *how* the models arrive at a conclusion. Full transcripts are written locally. You can replay the debate, swap moderators, change consensus mode, and tune tiebreak rules.

## Key Messages

1. **"Multi-model debate, not majority vote."** Models challenge each other across rounds. A well-argued minority position can override a weakly-justified majority — because the moderator reads the reasoning, not just the tally.
2. **"Built for MCP first."** Discover it in your AI client's tool list. Invoke it like any other tool. The host LLM never touches the API keys; the server holds them.
3. **"Setup takes one click, not one afternoon."** The macOS app installs the binaries, validates every API key, and emits a copy-paste MCP config snippet. The CLI is there when you want to script it.
4. **"Research-backed."** Adaptive break, tit-for-tat engagement, judge arbitration — straight from the MAD literature. We cite the paper because it matters.
5. **"Updates itself."** Sparkle for the app bundle — the setup app auto-updates and re-installs the bundled CLI + MCP binaries from `Contents/Resources/`. No custom updater, no surprise background processes.

## The Surfaces

The three user-facing binaries share the same `JointChiefsCore` engine. The keygetter is the trust anchor they all call into. Pick the one your workflow needs.

| Surface | When to use it | What it gives you |
|---|---|---|
| **MCP server** | Daily review from inside any MCP host | Tool-call invocation, host LLM passes code, consensus comes back inline |
| **CLI** (`jointchiefs`) | Pre-commit hooks, CI, scripting, debugging a stuck debate, one-off audits | Streaming SSE output, JSON mode, exit codes, stdin piping |
| **macOS setup app** | First install, key rotation, debate strategy tweaks, MCP wire-up verification | Live API key tests, curated model picker, standard MCP config snippet, moderator/consensus/tiebreaker config, "Configured AI tools" wire-up status, silent CLI install on first launch |
| **Keygetter** (under the hood) | Never directly | Sole Keychain ACL identity — the other binaries `Process`-spawn it for every key read/write |

The app is not required to use the product. The CLI is not required to use the MCP server. The MCP server is not required to use the CLI. Pick one, two, or all three.

## Feature Benefits

| Feature | Benefit |
|---|---|
| MCP-first design | Works inside the AI client you already live in — no context switch |
| Multi-model parallel review | Different architectures and training data catch different classes of bug |
| Hub-and-spoke debate (MAD protocol) | Models address each finding by title, take a position, defend it across rounds |
| Adaptive early break | Debate stops when positions converge — extra rounds add noise, not signal |
| Anonymized synthesis | Final consensus strips model identities so the moderator judges arguments, not brands |
| Configurable moderator and tiebreaker | Use the model you trust most as judge; pick consensus mode (unanimous, majority, weighted) |
| Streaming SSE on every provider | Tokens appear live in the CLI; the orchestrator can tell "slow" from "dead" |
| Local transcripts | Full debate written to disk — replay, audit, or pipe into your own tooling |
| One-click setup app | API key validation with live test buttons, copy-paste MCP config snippet |
| Auto-update | Sparkle for the app bundle; a re-install picks up new CLI + MCP binaries |
| Privacy-first | API keys stay local; no telemetry; the only network traffic is to providers you configured |

## Competitive Positioning

The MCP ecosystem hit 12,000+ servers by Q1 2026. Several do "ask another model." A handful do parallel multi-model review. None implement a structured debate protocol with research backing.

| Alternative | What it does | Where it falls short |
|---|---|---|
| **Single-model review** (default in any AI client) | One opinion from your daily-driver LLM | Self-reflection is unreliable — the MAD paper's core finding (Degeneration of Thought) |
| **Second Opinion MCP** (dshills, ProCreations, others) | Routes code to one external model for a "second look" | Still single-perspective — swaps one bias for another |
| **mcp-sage** | Second opinions on large codebases, single-model | No debate, no multi-model adversarial step |
| **Zen MCP** (BeehiveInnovations) | Multi-model collaboration with a `consensus` tool | Vote-based — surfaces opinions side-by-side without a structured debate protocol or judge arbitration |
| **pal-mcp-server** | Cross-model orchestration for Claude Code/Codex/Gemini CLI | Model-routing layer, not an adversarial debate engine |
| **multi_mcp** | Parallel multi-model chat and review for Claude Code | Parallel polling, no debate rounds, no MAD-style adaptive break |
| **Manual cross-tool review** | Run the same prompt through three CLIs yourself | Context switching, manual synthesis, no anonymization, doesn't scale |

**Joint Chiefs' wedge:** The only MCP server in the ecosystem that implements the MAD protocol end-to-end — adaptive break, tit-for-tat engagement, anonymized synthesis, judge arbitration. Backed by research, not just marketing.

## Website-Ready Material (jointchiefs.ai)

### Tagline (pick one)

- **"The MCP server that makes your AI models argue."**
- **"Multi-model code review with a moderator."**
- **"Four LLMs walked into a code review."**

Recommended: the first. Direct, slightly playful, communicates the entire mechanism in nine words.

### Headline candidates

1. **"Stop trusting one model to review its own work."**
2. **"Multi-model debate beats single-model review. Now it's an MCP server."**
3. **"Your code goes in. Four models argue. One consensus comes out."**

Recommended: candidate 1 for the hero, candidate 3 as a secondary subhead lower on the page.

### Subhead

Joint Chiefs is an MCP server that runs your code past OpenAI, Gemini, Grok, and Claude in parallel — then has them debate until consensus. Grounded in Multi-Agent Debate research. One-click macOS install. Zero telemetry.

### Primary CTAs

- **"Install on macOS"** → downloads the setup app DMG
- **"Use the CLI"** → jumps to install instructions for `jointchiefs`
- **"Read the protocol"** → links to ARCHITECTURE.md / MAD paper section

### Secondary CTA

- **"View on GitHub"** → repository

### Key benefit bullets (for above-the-fold)

- **Six providers, one consensus** — OpenAI, Anthropic, Gemini, Grok, plus two local options (Ollama and any OpenAI-compatible server like LM Studio / Jan / llama.cpp-server)
- **Structured debate, not majority vote** — built on MAD protocol research
- **Drops into your AI client** — MCP server, works with any MCP-aware host
- **One-click setup** — macOS app installs everything silently, validates every key, scans for MCP-aware clients to confirm wire-up
- **Auto-updates** — Sparkle for the app bundle (re-installs bundled CLI + MCP binaries)
- **Local-only** — no telemetry, no servers, your code never leaves your machine except to the providers you chose

## Brand Voice

- **Direct.** No marketing fluff. Developers respect clarity.
- **Confident.** This is the right way to do AI code review. Cite the research, then move on.
- **Technical.** API keys, MCP tool calls, EdDSA signatures, SSE streaming. Speak the language.
- **Minimal.** One sentence per idea. No paragraphs where bullets work.
- **Slightly playful, never cute.** "Four LLMs walked into a code review" is fine. Emoji is not.

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial value proposition (CLI-only product) |
| 2.0 | 2026-04-16 | Reframed for v2 launch under jointchiefs.ai. Lead with MCP server framing. Documented three-surface product (MCP / CLI / setup app). Sharpened MAD-vs-vote-based-consensus pitch with explicit research citation. Updated competitive table for 2026 ecosystem (Zen MCP, Second Opinion variants, mcp-sage, pal-mcp-server, multi_mcp). Dropped deferred menu bar app. Added website-ready material: tagline, headline candidates, CTA copy, key benefit bullets. |
| 2.1 | 2026-04-20 | Website + repo links added to header. Corrected the "updates itself" messaging across Key Messages, Feature Benefits, and key-benefit bullets — aligned with the lean-baseline direction (Sparkle for the app bundle only; no custom EdDSA-signed updater for the CLI/MCP binaries). |
| 2.2 | 2026-04-26 | Reconciled provider count and surface count with shipping reality. Bumped "five providers" → six in the lead pitch and key-benefit bullets — adds the v0.4.0 OpenAI-compatible support (LM Studio, Jan, llama.cpp-server, Msty, LocalAI) as a second local-model option alongside Ollama. Reframed "three surfaces" → three user-facing surfaces plus the keygetter as a trust-anchor binary, matching how PRD / ARCHITECTURE / CLAUDE.md describe it. The Surfaces table grew a Keygetter row noting users never invoke it directly. Setup-app description bullet now lists the five sections in display order (How to Use, API Keys, Roles & Weights, MCP Config, Privacy) and notes the silent first-launch CLI install + "Configured AI tools" wire-up panel. |
