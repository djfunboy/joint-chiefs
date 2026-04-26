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

### 2026-04-23: Created + committed files Chris never asked for
**What happened:** Chris asked for a prompt to start his next session. I wrote one, AND also created `tasks/SESSION-HANDOFF-2026-04-23.md`, committed it, and pushed it to the public app repo — none of which he asked for. Same pattern repeated earlier in the session: removed the open-source pill from UsageView when he'd only criticized a section header; added button chrome to the Privacy GitHub link when he'd never asked for it.
**Rule:** **Do not create, commit, push, or delete any file that wasn't explicitly requested.** A prompt is a prompt; a handoff doc is a handoff doc. They're different deliverables. When in doubt about scope, finish the explicit ask and stop. Especially for the Joint Chiefs public repo: session handoff docs contain internal operational notes and belong local-only (`tasks/SESSION-HANDOFF-*.md` is now gitignored).

### 2026-04-23: Shipped Sparkle integration as a release without explicit permission
**What happened:** Chris said "lets tackle 1" referring to follow-up item 1 (Sparkle framework integration). Claude interpreted that as the full arc — integrate, build, sign, notarize, push commits to `origin/main`, bump cask SHA. Treated earlier session directives ("just keep going", "proceed with release") as standing authorization. Pushed commit `ae8dfe0` to the public repo and bumped the cask to v0.2.0 before Chris had approved a release or confirmed the version number.
**Rule:** **HARD RULE — never ship a release without explicit, in-the-moment permission and version-number confirmation.** A release is: any public git push that bumps version metadata, any tag, any `gh release`, any appcast update, any artifact upload, any website download-button change, or any cask version bump. Before any of those:
  1. Stop and ask: "Ready to ship as v<X.Y.Z>?"
  2. Wait for explicit yes + version number confirmation — do not proceed on assumed-standing authorization from earlier in the session.
  3. If Chris gives a scope direction like "lets tackle N" where N is a follow-up, assume it's scoped to the *technical work*, not the release. Ship only when he says "ship v<X.Y.Z>" or equivalent.
  4. This overrides any "just keep going" / "proceed" / "keep moving" signals earlier in the session. Release authorization is per-release, not per-session.

### 2026-04-26: System clock drift silently blocked notarization
**What happened:** During the v0.5.0 release, the first `xcrun notarytool submit` attempt failed instantly with `RequestTimeTooSkewed`. Apple's notary service rejects submissions when the local clock differs from real time by more than ~15 minutes; ours was 23h 35m behind because `timed` had wedged with auto-time-sync still toggled on. `codesign` had even printed a clear warning ("timestamps differ by 84957 seconds — check your system clock") earlier in the flow but it was easy to miss. Fix took two minutes (toggle Date & Time auto-sync off/on, or `sudo sntp -sS time.apple.com`), but it was confusing because the toggle showed as enabled.
**Rule:** Before any release that involves Apple's services (notarytool, App Store Connect, etc.), confirm the system clock matches real-world time. Quick check: `date -u` should match the `Date:` header from `curl -sI https://www.apple.com`. If they disagree by more than a few seconds, fix the clock before doing anything else — `sudo sntp -sS time.apple.com` forces a sync even when `timed` is wedged. Auto-sync being "on" in System Settings does not guarantee the daemon is actually working.

### 2026-04-23: Shipped v0.2.0 and v0.3.0 DMGs that crashed on launch for every fresh downloader
**What happened:** The SwiftPM release build produced `jointchiefs-setup` with `LC_RPATH` entries pointing only at `/usr/lib/swift`, `@loader_path`, and the Xcode toolchain — no `@executable_path/../Frameworks`. `scripts/build-app.sh` copied `Sparkle.framework` into `Contents/Frameworks/` and then signed + notarized + stapled the bundle, but nothing ever patched the rpath. Sparkle's install name is `@rpath/Sparkle.framework/...`, so dyld couldn't resolve it and the process died before any Swift code ran. Gatekeeper accepted the DMG (signing and notarization don't validate rpath-vs-install-name compatibility), so v0.2.0 and v0.3.0 shipped looking fine. The failure was invisible during development because `/Applications/Joint Chiefs.app` still held v0.1.0 (pre-Sparkle, no rpath needed) — macOS fell back to launching that copy whenever the broken build failed to start, making it look like the new build "worked." Sparkle couldn't rescue v0.2.0/v0.3.0 users either, because the app Sparkle lives inside never reached `main()`.
**Rule:** **Every release passes a cold-machine smoke test before `gh release create`:** (1) `rm -rf "/Applications/Joint Chiefs.app"` so there's no fallback copy, (2) mount the just-built `Joint-Chiefs.dmg`, drag-install the app, (3) launch it, (4) confirm the process stays alive and the first-run window appears. Any dyld failure will print to Console and the app will vanish — that's the failure mode this check catches. Signing, notarization, and `spctl -a` verdicts are necessary but not sufficient — they only verify identity, not runtime linkage. Also: `scripts/build-app.sh` now patches the rpath with `install_name_tool -add_rpath "@executable_path/../Frameworks"` after Sparkle is copied; future builds get it automatically.

### 2026-04-26: Public-facing README drifted across two releases without being caught
**What happened:** v0.4.0 shipped LM Studio / OpenAI-compatible support; v0.5.0 shipped the Configured AI tools panel + sidebar update-status footer. Neither release reconciled the README. Three weeks later, Chris caught the drift himself by scrolling github.com/djfunboy/joint-chiefs: the "How it works" diagram still showed 3 spokes (no Anthropic-as-spoke, no Ollama, no OpenAI-compatible), the moderator was hardcoded to "Claude moderates" instead of "default: Claude," the Configuration env-var table was missing `OPENAI_COMPATIBLE_BASE_URL` / `OPENAI_COMPATIBLE_MODEL`, and the Contributing line implied Mistral/DeepSeek were unreachable when both work today via the OpenAI-compat path. The pre-release checklist's step-5 doc scan listed `README.md` but didn't enumerate *which* facts to check, so the scan kept passing while the assertions silently aged out.
**Rule:** The pre-release doc scan (CLAUDE.md "Pre-release review" step 5) must verify the README's *specific factual assertions* against shipping code, not just confirm the file is touched. The verification list:
  1. **"How it works" diagram** — spoke set matches `ProviderType` cases; moderator framed as "default: Claude" (configurable), not "Claude moderates" (hardcoded).
  2. **Configuration env-var table** — every env var read by code (`grep -rn "ProcessInfo.processInfo.environment\\|getenv" Sources/JointChiefsCore`) is in the table.
  3. **CLI flags table** — every `@Option`/`@Flag` in `ReviewCommand.swift` and `ModelsCommand.swift` is in the table.
  4. **Test count** in the Development snippet matches `swift test` actual count.
  5. **Project layout** matches `ls Sources/`.
  6. **Surfaces table** — binary names + descriptions match `Package.swift` products.
  7. **Contributing roadmap line** — claimed-future capabilities match what the v0.4.0 OpenAI-compat path already enables (don't say something is unsupported when users can reach it today).
This is in addition to the existing doc list (CLAUDE.md current-state line, BUILD-PLAN, PRD, ARCHITECTURE, DATA-MODEL, VALUE-PROPOSITION, DESIGN-SYSTEM, KNOWN-ISSUES). Run the full reconciliation *before* tagging, not after Chris notices it on GitHub.

### 2026-04-26: Website Quickstart shipped two installation bugs that would brick a new user
**What happened:** The jointchiefs.ai homepage Quickstart had a `cp` command that only copied the `jointchiefs` CLI (missing `jointchiefs-mcp` and `jointchiefs-keygetter`), and the MCP config snippet's `command` path was `/usr/local/bin/jointchiefs-mcp` — the Intel-era Homebrew prefix. Apple Silicon (the only supported platform) uses `/opt/homebrew/bin/`, so the snippet would never resolve. Either bug alone would block setup; together they made the Quickstart purely decorative for anyone following it literally. The bugs were caught only because Chris scrolled the live site and noticed.
**Rule:** Every app release that touches install paths, binary names, install scripts, the keygetter, or the MCP server's command surface requires a verification pass against the website Quickstart and download page **before** tagging. The verification list, run from inside `~/Dropbox/Build/Joint Chiefs Website/`:
  1. **`index.html` `#quickstart` step 01 cp command** — every executable product in `Package.swift` (`jointchiefs`, `jointchiefs-mcp`, `jointchiefs-keygetter`) is in the line. Verify against `swift package describe --type json | jq '.products[] | select(.type.executable) | .name'` or just `grep '.executable(' Package.swift`.
  2. **`index.html` `#quickstart` step 03 MCP snippet `command`** — path matches the actual install destination. Apple Silicon is `/opt/homebrew/bin/`, never `/usr/local/bin/` (Intel prefix). Cross-check against `mcpBinaryPath` in `JointChiefs/Sources/JointChiefsSetup/Views/MCPConfigView.swift`.
  3. **`download.html` "Command line" cp command** — same as item 1; the two snippets must stay in sync.
  4. **`guide/mcp.html` step 02 MCP snippet `command`** — same path as item 2.
  5. **`guide/cli.html` env-var table and flag table** — every env var read by `JointChiefsCore` (`grep -rn "ProcessInfo.processInfo.environment\\|getenv" Sources/JointChiefsCore`) and every `@Option`/`@Flag` in `Sources/JointChiefsCLI/` is listed.
  6. **`setup-guide.md` ↔ in-app `aiPrompt` ↔ `llms.txt`** — paths, tool name (`joint_chiefs_review`), restart guidance, and rate-limit numbers match. Treat the trio as one logical surface; a change to any one requires the others.
  7. **`download.html` requirements table** — provider list matches `ProviderType` enum cases.
  8. **JSON-LD `softwareVersion` in `index.html`** and the `<announce-bar>` text on `guide/*.html` — bumped to the new release.
This is a parallel surface to the in-repo README/docs scan from the prior 2026-04-26 lesson — the website is just as user-facing and just as subject to drift. Run it before tagging the app release. Both lists are part of step 5 of the "Pre-release review (public repo)" in CLAUDE.md.

## Common Traps

_To be populated during development._
