# Session Handoff — 2026-04-21

Resume pointer for the next Joint Chiefs session. Context was cleared after this file was written. This file is self-contained — you don't need prior conversation to pick up.

## What This Session Delivered

### App repo (github.com/djfunboy/joint-chiefs, public, MIT)
- **Three clean commits on `main`** capturing all prior-session work: setup app + MCP server + Agentdeck design system (4f2eba1), doc sync for setup app + weighting + MCP + open-source release (eafd1fd), prototypes + build scripts + session handoffs (d1a2fa0).
- **All docs synced** (a7076bf): CLAUDE.md now describes the four-surface product (CLI, MCP, setup app, keygetter), test count corrected 34 → 60, architecture tree lists every source dir, hard rules include streaming-SSE / no-client-enumeration / stdio-only-MCP. README, PRD, ARCHITECTURE, BUILD-PLAN, VALUE-PROPOSITION, DESIGN-SYSTEM all updated.
- **60 tests passing.** All targets build clean.
- **Local commits NOT pushed** — waiting on user authorization per the "don't push without asking" rule. `main` is 4 commits ahead of `origin/main`.

### Website (jointchiefs.ai, private repo github.com/djfunboy/joint-chiefs-website)
- **Live at https://jointchiefs.ai** via Netlify (site ID `79794bf5-ed42-41bb-9610-a6cd57a79a12`). Custom domain + Let's Encrypt SSL configured via the Netlify REST API.
- **Ten long-form articles published** under `/articles/`, backdated 2026-03-23 → 2026-04-19 across the series. Topics: single-model-review problems → MAD research → model strengths → anonymization → DoT → consensus modes → adaptive termination → per-provider weighting → MCP → 2026 overview (flagship).
- **All 10 articles rewritten in Chris Doyle's voice** on 2026-04-21 (bf91328). Canonical voice file: `~/Dropbox/Build/Content/voice-of-chris-doyle.md`. Every long-form content task MUST read this file before writing — see `tasks/lessons.md`.
- **LinkedIn + X share buttons** added to all 10 articles (d5828e1). Matrix.watch got the same treatment (separate repo, same day).
- **SEO + AIO wired:** every article has Article + FAQPage JSON-LD schema, unique meta descriptions, OG + Twitter cards, sitemap.xml with per-article `<lastmod>`, `llms.txt` with summary per article.

### Voice rule locked in memory
- Memory: `feedback_chris_voice.md` — "always load `/Users/chrisdoyle/Library/CloudStorage/Dropbox/Build/Content/voice-of-chris-doyle.md` before writing any article, blog, or marketing copy."

## The Mission for the Next Session

**Get Joint Chiefs fully ready to launch on https://jointchiefs.ai.**

The website is live. The articles are shipped. What's missing is the actual app artifact — a signed, notarized `.dmg` that users can download from `/download` and that Sparkle can update. Until that exists, the Download button on the site leads to build-from-source instructions, not a real install.

### Launch criteria — the full list

**Code (local, low-risk):**

1. **Fix active bugs in `JointChiefsCore`:**
   - Anthropic consensus occasionally emits raw JSON in `Finding.description` — bug in `ConsensusBuilder.synthesizeWithModel`, same shape as the fence-stripping fix in commit `8bfa1a8` but in the synthesis path. Write a failing test first, then fix.
   - `runReviewStreaming` doesn't wire `continuation.onTermination` to cancel the unstructured `Task` it spawns — long debates keep running after CLI Ctrl-C.
   - Duplicate `runReview` / `runReviewStreaming` paths — same workflow twice. Consolidate into one or factor the shared core out.
   - No validation on negative `debateRounds` in `DebateOrchestrator.init`. Guard + throw.
   - Empty debate rounds silently continue when every provider fails in a round. Detect and break.

2. **Implement the three queued features (from SESSION-HANDOFF-2026-04-18.md):**
   - **DebateOrchestrator refactor (#15):** primary init `(providers:moderator:tiebreaker:strategy:)`; branch final consensus on `strategy.consensus`; wire tiebreaker routing; CLI and MCP load via `StrategyConfigStore.load()`.
   - **MCP rate limiting (#26):** one concurrent review, 30/hour cap, cancel on stdin close.
   - **URLSession redirect Authorization-stripping delegate (#25):** one shared delegate across all five providers.

3. **Setup app polish (tracked in `KNOWN-ISSUES.md`):**
   - RootView / Sidebar still use `Color.accentColor` and `Color(nsColor: .underPageBackgroundColor)`. Migrate to Agentdeck tokens.
   - VoiceOver + Dynamic Type pass on all five views (tracked in Phase 9).
   - `AgentInputStyle` placeholder color is the system default — fix with custom overlay.

**Bundling + distribution (needs user credentials and is externally visible):**

4. **App icon** — create `Resources/AppIcon.icns` + wire `CFBundleIconFile` in `scripts/Info.plist`. No icon today; Finder shows a generic one.

5. **Build the release bundle** — `scripts/build-app.sh` runs `swift build -c release` and assembles `build/Joint Chiefs.app`. Verify it launches and stays foregrounded (it currently does via `NSApp.setActivationPolicy(.regular)`).

6. **Code-sign all four binaries with Developer ID:**
   - `jointchiefs`, `jointchiefs-mcp`, `jointchiefs-setup` → sign with the user's Developer ID Application certificate.
   - `jointchiefs-keygetter` → sign with `--identifier com.jointchiefs.keygetter` specifically (this identifier is what the Keychain ACLs authorize; changing it invalidates saved keys).

7. **Notarize and staple the app bundle** — `xcrun notarytool` + `xcrun stapler`. Needs Apple ID + app-specific password.

8. **Create the DMG** — `create-dmg` or `hdiutil`. Sign the DMG too.

9. **Sparkle integration** — populate `jointchiefs.ai/appcast.xml` with a real `<item>` containing version, build, EdDSA signature, release notes, and download URL. Currently a placeholder skeleton.

**Website wiring (needs commit to the private website repo + redeploy):**

10. **Upload the DMG to the website** — Netlify serves static assets from the repo, so the DMG goes in the repo at `/Joint Chiefs.dmg` (or similar). Warning: Git LFS if the DMG is large; verify Netlify's size limits.

11. **Update website `Download` button** — currently `/download` page has build-from-source instructions. Wire the button to the real `.dmg` URL. Update `sitemap.xml` and `llms.txt` if the URL changes.

12. **Verify end-to-end download + install flow** — fresh download from the site, open, drag to Applications, first-run disclosure, add one API key, run one review via the CLI or MCP.

**Documentation + release hygiene:**

13. **Write `SECURITY.md`** — documenting the keygetter-ACL security model, env-var fallback, stdio-only MCP, and how to report vulnerabilities.

14. **Push the app repo** — currently 4 commits ahead of `origin/main` (including this handoff once it's committed). Ask user authorization first per the project rule.

15. **Create a GitHub release** — tag the notarized build, attach the DMG, paste the release notes that will also land in `appcast.xml`.

16. **End-to-end QA** — specifically:
    - Real Keychain round-trip (setup app writes key via keygetter, CLI reads it back, review runs).
    - MCP integration test from any MCP-aware host.
    - CLI when no API keys configured (should print clean error, not crash).
    - CLI when only one provider configured (should still produce useful output).

## Critical Rules (do not violate)

- **Voice:** `~/Dropbox/Build/Content/voice-of-chris-doyle.md` is the canonical voice for any long-form content. Load it before writing. Enforced rule in memory.
- **Streaming SSE always.** Non-streaming LLM calls are banned — they time out.
- **Never enumerate specific MCP clients or AI CLIs.** Use "any MCP client" / "any AI CLI" in docs, UI, comments, commit messages.
- **Stdio-only MCP.** Network transports are architecturally prohibited.
- **Design system:** no hex literals or CGFloat literals in any `JointChiefsSetup` view. Use `Color.agent*`, `Font.agent*`, `AgentSpacing.*`, `AgentRadius.*`, and the `Agent*ButtonStyle` button styles.
- **Security baseline:** Developer ID + notarization + Sparkle. No YubiKey, no custom updater, no XPC. Match the baseline of the user's other 10 macOS apps.
- **Don't push without asking.** The user commits directly to main but explicitly approves pushes.
- **Don't auto-endorse subagent creative output.** Taglines, naming, copy, design choices are relayed as proposals.
- **Don't push back on scope expansion.** User prefers wider v1 over faster ship — treat scope additions as decisions, not questions.

## Key Facts and IDs

- **App repo:** `github.com/djfunboy/joint-chiefs` (public, MIT)
- **Website repo:** `github.com/djfunboy/joint-chiefs-website` (private, MIT)
- **Netlify site ID:** `79794bf5-ed42-41bb-9610-a6cd57a79a12`
- **Netlify project:** `jointchiefs-website` on team `djfunboy` (Outergy)
- **Custom domain:** `jointchiefs.ai` — apex A record → `75.2.60.5`; `www` CNAME → `jointchiefs-website.netlify.app`
- **Primary MAD citation:** Liang et al. 2023, arXiv:2305.19118
- **Test count:** 60 passing (as of commit `a7076bf`)
- **Apple Developer identifier for keygetter:** `com.jointchiefs.keygetter` (do not change — Keychain ACLs depend on it)

## Recommended Execution Order

Do the safe local work first. Hold the externally-visible steps (push, DMG upload, GitHub release, appcast update) until the user explicitly authorizes.

1. **Code quality first** (steps 1, 2, 3 above) — fix bugs, refactor Orchestrator, setup-app polish. Tests keep passing. No pushes yet.
2. **Build verification** (step 5) — confirm `scripts/build-app.sh` still produces a working bundle after the code changes.
3. **App icon** (step 4) — this is the last local-only piece.
4. **Ask user for authorization** to proceed with signing, notarization, DMG, website update, and release.
5. **Signing + notarization + DMG** (steps 6-8) — needs user's Developer ID cert and Apple ID.
6. **Website wiring + Sparkle** (steps 9-11) — commit to website repo, push, redeploy via Netlify.
7. **End-to-end QA** (step 16) — then release (step 15).

## Files to Read First in the Next Session

1. `CLAUDE.md` — project rules + current state.
2. `tasks/lessons.md` — hard rules accumulated from corrections.
3. `tasks/SESSION-HANDOFF-2026-04-21.md` — this file.
4. `docs/KNOWN-ISSUES.md` — active bugs + roadmap-adjacent items + QA gaps.
5. `docs/ARCHITECTURE.md` — four-surface design, security model, distribution section.
6. `docs/BUILD-PLAN.md` — phase-by-phase status. Phase 10 is the launch phase.

## Status At Handoff

- App: ✅ 60 tests passing, 4 unpushed commits on main, no code regressions
- Website: ✅ live at jointchiefs.ai, 10 articles in Chris's voice with share buttons, SEO + AIO wired
- Voice file: ✅ memorialized as a rule in memory (feedback_chris_voice.md)
- Matrix.watch: ✅ share buttons added to all 14 articles (sibling project, same day)
- DMG: ❌ not built, not signed, not notarized
- Download button on jointchiefs.ai: ❌ points at build-from-source instructions, not a real installer
- Sparkle appcast.xml: ❌ placeholder skeleton, no `<item>` entries
- SECURITY.md: ❌ not written

If you only have time for one thing next session, it's the bug fixes + refactors (steps 1-3). Those are self-contained, improve reliability, and don't require the user's physical Developer ID keychain to land.
