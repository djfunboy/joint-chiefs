# Joint Chiefs — Lessons

> **Review at every session start.** Every entry below is a hard rule, not a suggestion.
> Update after every correction from the user — immediately, before continuing other work.

### 2026-04-08: Should have used streaming API calls from the start
**What happened:** Built all providers using `urlSession.data(for:)` which waits for the complete response. This caused timeouts across multiple test runs. Spent several iterations trying to fix timeouts by adjusting timeout values, reducing prompt size, etc. when the root cause was the non-streaming API pattern.
**Rule:** When building tools that call LLM APIs, use streaming (SSE) by default. Non-streaming calls to LLMs are almost never the right choice — they're slow, they timeout, and they prevent showing progress. Think through the API interaction pattern before building features on top of it.

### 2026-04-08: Think through fundamentals before building features
**What happened:** Built 4 providers, orchestrator, CLI, hub-and-spoke architecture, adaptive break, and anonymous findings before realizing the basic API call pattern was wrong. Each iteration added complexity on top of a broken foundation.
**Rule:** Before building features, validate the core interaction works end-to-end at the simplest level. One provider, one call, streaming response. Then build up.

### 2026-04-20: Enumerated specific MCP clients in docs and UI
**What happened:** Described Joint Chiefs as "an MCP server for Claude Code, Claude Desktop, and Cursor" across docs, UI labels, and comments. Chris uses Warp, which the three-client list implicitly excluded. Even "fixing" a two-client list to three was the wrong move — the product is MCP-spec-conformant and works with any MCP client.
**Rule:** Never list specific MCP clients or AI CLIs as the compatibility set. Use "any MCP client", "any MCP-aware host", or "any AI CLI" instead. This applies to PRD, ARCHITECTURE, BUILD-PLAN, VALUE-PROPOSITION, README, UI labels, code comments, and setup app copy. The enumerated list of *providers the product calls* (OpenAI, Gemini, Grok, Claude, Ollama) stays — those are real features, not a compatibility assertion.

## Common Traps

_To be populated during development._
