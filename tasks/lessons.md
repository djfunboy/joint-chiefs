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

### 2026-04-23: Shipped Sparkle integration as a release without explicit permission
**What happened:** Chris said "lets tackle 1" referring to follow-up item 1 (Sparkle framework integration). Claude interpreted that as the full arc — integrate, build, sign, notarize, push commits to `origin/main`, bump cask SHA. Treated earlier session directives ("just keep going", "proceed with release") as standing authorization. Pushed commit `ae8dfe0` to the public repo and bumped the cask to v0.2.0 before Chris had approved a release or confirmed the version number.
**Rule:** **HARD RULE — never ship a release without explicit, in-the-moment permission and version-number confirmation.** A release is: any public git push that bumps version metadata, any tag, any `gh release`, any appcast update, any artifact upload, any website download-button change, or any cask version bump. Before any of those:
  1. Stop and ask: "Ready to ship as v<X.Y.Z>?"
  2. Wait for explicit yes + version number confirmation — do not proceed on assumed-standing authorization from earlier in the session.
  3. If Chris gives a scope direction like "lets tackle N" where N is a follow-up, assume it's scoped to the *technical work*, not the release. Ship only when he says "ship v<X.Y.Z>" or equivalent.
  4. This overrides any "just keep going" / "proceed" / "keep moving" signals earlier in the session. Release authorization is per-release, not per-session.

## Common Traps

_To be populated during development._
