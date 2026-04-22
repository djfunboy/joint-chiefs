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

### 2026-04-21: Wrote articles in a generic "technical writer" voice
**What happened:** Shipped 10 articles on jointchiefs.ai in a polished but generic voice. Chris wanted them in his actual voice — the one in `~/Dropbox/Build/Content/voice-of-chris-doyle.md`. Had to rewrite all 10 and rename two banned-phrase titles ("Revolution", "State of the Art").
**Rule:** For any long-form content (articles, blog posts, marketing copy, website hero copy), always read `/Users/chrisdoyle/Library/CloudStorage/Dropbox/Build/Content/voice-of-chris-doyle.md` before writing. Treat the Part 4 checklist and Part 3 negative examples as hard constraints. Banned vocabulary (leverage, optimize, holistic, transformative, revolutionize, state-of-the-art, unlock, journey, empower, etc.) never appears — even in headings, IDs, or titles. Distinctive tells: "I am" not "I'm", sentence fragments for punch, dashes over semicolons, opinions stated as facts, reader addressed as "you", short paragraphs (1-4 sentences).

### 2026-04-21: Shipped article pages without social share buttons
**What happened:** Published 10 articles to jointchiefs.ai (and 14 existing articles on matrix.watch) without LinkedIn/X share buttons. Chris flagged it — the Stash template includes them, and every article template in the Dropbox/Build projects should too.
**Rule:** Every article page gets a LinkedIn + X share block directly under the article-meta / header, before the body. CSS classes `.social-share` and `.share-button`, URL-encoded article URL + title, `aria-label` on each button, `target="_blank" rel="noopener"`. Style the buttons with each site's existing theme tokens (warm-charcoal Agentdeck for Joint Chiefs, green-on-black for matrix.watch, etc.) — never use hardcoded colors that don't match the site's palette.

## Common Traps

_To be populated during development._
