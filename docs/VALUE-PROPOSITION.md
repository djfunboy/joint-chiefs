# Joint Chiefs — Value Proposition

**Version:** 1.0
**Last Updated:** 2026-04-08

## Core Value Proposition

**One command. Multiple AI reviewers. Consensus-driven recommendations.**

Joint Chiefs orchestrates code review across multiple LLMs — GPT, Gemini, Grok, and more — running structured debates where models challenge each other's findings and converge on actionable recommendations. Triggered from any AI coding tool with a single command.

## Problem Statement

AI-assisted code review today gives you one model's opinion. But every model has blind spots:
- GPT might catch a security issue that Gemini misses
- Gemini might spot a performance concern that Grok overlooks
- Grok might flag an architectural problem that GPT ignores

There's no way to get multiple AI perspectives, have them debate, and receive a single consensus recommendation — especially not from within the CLI tools developers already use.

## Target Audience

### Primary: Solo Developers Using AI Coding Tools
Developers who use Claude Code, Codex, Gemini CLI, or Grok daily for coding tasks. They already have API keys for multiple providers and want higher-confidence code review without switching tools.

### Secondary: Small Engineering Teams
Teams that want consistent, multi-perspective code review integrated into their workflow.

## Key Messages

1. **"Your code deserves more than one opinion."** — Single-model review has blind spots. Joint Chiefs fills them.
2. **"Works where you already work."** — Trigger from Claude Code, Codex, Gemini CLI, or any tool that runs shell commands.
3. **"Debate, don't just review."** — Models don't just list findings. They challenge each other across multiple rounds until consensus emerges.
4. **"Summary out, transcript in."** — Get a concise consensus in your terminal. Browse the full debate in the app when you're curious.

## Feature Benefits

| Feature | Benefit |
|---|---|
| Multi-model parallel review | Catches issues no single model would find alone |
| Structured debate rounds | Models challenge each other, reducing false positives |
| Consensus synthesis | One clear recommendation, not 3 separate reports to parse |
| Universal CLI trigger | No workflow change — works from any AI coding tool |
| macOS menu bar app | Always running, zero friction, browse transcripts anytime |
| Configurable goals | "Security audit" vs "performance review" vs "architecture check" |
| Transcript viewer | See how models debated — learn what each model is good at |

## Competitive Positioning

| Alternative | Limitation | Joint Chiefs Advantage |
|---|---|---|
| Single-model review (default) | One perspective, blind spots | Multiple models, consensus |
| pal-mcp-server | Claude Code only, no debate | Any CLI tool, structured debate |
| brainstorm-mcp | No native app, no transcript UI | macOS app with browsable transcripts |
| multi_mcp | No universal trigger, no settings UI | CLI + HTTP + MCP, native macOS settings |
| Manual multi-tool review | Context-switching, manual synthesis | Automated orchestration, single command |

## Brand Voice

- **Direct.** No marketing fluff. Developers respect clarity.
- **Confident.** This makes code review better. Period.
- **Technical.** Speak the language of the audience. API keys, models, CLI flags.
- **Minimal.** One command. Summary back. Done.

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial value proposition |
