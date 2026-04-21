# Session Handoff — 2026-04-20

Resume pointer for the next Joint Chiefs session. Context was cleared after this file was written. This file is self-contained — you don't need prior conversation to pick up.

## What This Session Delivered

### Website — built out end-to-end
Sits at `~/Dropbox/Build/Joint Chiefs Website/`. **Not yet a git repo** (important — see handoff tasks).

- **Six HTML pages** live: `index.html` (redesigned per Agentdeck), `download.html`, `guide/mcp.html`, `guide/cli.html`, `guide/security.html`, `404.html`.
- **Shared `styles.css`** (926 lines) — `index.html`'s inline `<style>` block was extracted; every page now links it. Agentdeck tokens applied: warm-charcoal palette, monospace-as-identity, 4px spacing grid, 6px button radius, compact 20px H1. **JC blue `#0285ff` preserved** as `--accent-strong` (primary CTA + focus rings + `status.info`).
- **Announcement bar** at viewport top (36px, `#0a0706`, NEW badge + MIT repo link). Nav pushed to `top: 36px`; `main` has `padding-top: 101px`.
- **Pixel-art hero wordmark** — `JOINT / CHIEFS` in Press Start 2P, flat white, no texture/glow (earlier Minecraft-stone variant was rejected).
- **Favicons + OG card** generated via Swift+CoreGraphics scripts (`scripts/make-favicon.swift` = 5×7 pixel "JC" on `#0d0d0d`; `scripts/make-og-image.swift` = 1200×630 warm-charcoal with bold mono title + JC-blue underline bar). Rerun either script to regenerate.
- **`llms.txt`** — AI-crawler summary at website root with public-repo URLs.
- **`sitemap.xml`** + **`robots.txt`** (blocks `.dmg` indexing) + **`appcast.xml`** placeholder.
- **Copy buttons on code blocks** — inline `copyCodeBlock` vanilla JS per page. Strips leading `$` shell prompts so copied text is runnable.

### App — design system scaffolded
Sits at `~/Dropbox/Build/Joint Chiefs/JointChiefs/Sources/JointChiefsSetup/DesignSystem/`.

Three new Swift files, all compile cleanly (`swift build --target JointChiefsSetup` → exit 0):

- **`AgentdeckTokens.swift`** — every Color the app uses (`agentBgDeep`, `agentBrandBlue`, `agentSuccess`, etc.) + `AgentSpacing`, `AgentRadius`, `AgentLayout`, `AgentShadow` enums.
- **`AgentdeckTypography.swift`** — `Font.agentXS` through `.agentLg` mono scale plus `.agentDialogTitle` / `.agentHumanName` for the documented sans-for-prose surfaces. `.agentUppercaseCaption()` view helper for panel-header tracking.
- **`AgentdeckButtonStyle.swift`** — six `ButtonStyle` structs (`AgentPrimaryButtonStyle`, `Secondary`, `Ghost`, `Merge`, `Danger`, `Toolbar`) with `.agentPrimary` / `.agentSecondary` etc. convenience wrappers.

### Documentation
- **`Joint Chiefs Website/docs/DESIGN-SYSTEM.md`** — Agentdeck system mapped to CSS custom properties, component recipes, what-not-to-do rules.
- **`Joint Chiefs/docs/DESIGN-SYSTEM.md`** — Agentdeck system mapped to SwiftUI tokens + component recipes. Explains the "sans for prose / mono for technical" rule.
- **Both `CLAUDE.md` files** updated — design system is mandatory reading, tokens must come from the `Agentdeck*` files / `styles.css`, no hardcoded hexes/pixels.
- **Website `BUILD-PLAN.md` + `KNOWN-ISSUES.md`** updated — Phase 2 (design system + assets) marked complete.
- **App `KNOWN-ISSUES.md`** updated — added the setup-app token-migration items as a dedicated section.
- **`tasks/lessons.md`** — already contains the "don't enumerate specific MCP clients" rule from earlier.

### Repo visibility
- **`github.com/djfunboy/joint-chiefs` is now PUBLIC** (MIT licensed). Pushed commits include everything up through `9a8b40c` plus `0b266a8` (open-source pre-flight) and `b784ca1`.
- **Secret scan run** over all 5 commits on history — zero matches against `sk-`, `sk-ant-`, `sk-proj-`, `xai-`, `AIza…`, `AKIA…`, `gh[pousu]_`, bearer tokens, or private-key headers.
- **Joint Chiefs Website folder is NOT a git repo** — safe from accidental push, but has to be initialized before Netlify deploy.

## Pending Work — Prioritized

### 1. Apply Agentdeck tokens to existing setup-app views (BIGGEST)
Five views, all under `JointChiefs/Sources/JointChiefsSetup/Views/`:

- `DisclosureView.swift`
- `KeysView.swift`
- `RolesWeightsView.swift`
- `InstallView.swift`
- `MCPConfigView.swift`

For each, replace ad-hoc `.padding()`, `.font()`, `.background(Color.gray)` etc. with the `Agentdeck*` tokens. Specs per view are in `docs/KNOWN-ISSUES.md` under "Design System Adoption (Setup App)" and `docs/DESIGN-SYSTEM.md` under "Application to Setup App Views."

**Rule:** never hardcode a hex or CGFloat in a view. If a token doesn't exist for what you need, add it to `AgentdeckTokens.swift` first and document it in `docs/DESIGN-SYSTEM.md`.

### 2. Initialize git for the Joint Chiefs Website + deploy
The website folder is ready to ship but isn't under version control.

Recommended path:
1. `cd "~/Dropbox/Build/Joint Chiefs Website"`
2. `git init && git add -A && git commit -m "Initial commit: Joint Chiefs website v1"`
3. Create a new public GitHub repo (`djfunboy/joint-chiefs-website` is the natural name).
4. Push.
5. Wire Netlify to the repo. DNS for `jointchiefs.ai` needs to be pointed to Netlify.
6. Submit `sitemap.xml` to Google Search Console + Bing Webmaster Tools.

### 3. Mobile pass on the website
`styles.css` has `@media (max-width: 720px)` breakpoints for sections and the announce bar, but only desktop was visually verified in this session. Likely touch-ups needed: hero CTA wrapping, pixel-wordmark scaling, table overflow on guide pages.

### 4. Commit the 24+ uncommitted files on the app repo
Long list of modified files (see `git status`). One bundled commit for the design-system + setup-app-scaffold work is probably right; a separate commit for docs is also fine.

### 5. Sanitize the "Degree Daddy" reference in public commit history
The current `CLAUDE.md` in HEAD is already sanitized ("our other macOS apps"), but earlier commits may retain the literal name. Only do a history rewrite if this actually matters for the public repo; otherwise leave it — you already flagged it as low-severity.

### 6. Still queued from before
These were pending before this session started (see `tasks/SESSION-HANDOFF-2026-04-18.md`):

- **`DebateOrchestrator` refactor (#15)** — primary init takes `providers: moderator: tiebreaker: strategy:`; branch final consensus on `strategy.consensus` (moderatorDecides / strictMajority / bestOfAll / votingThreshold); tiebreaker routing; CLI/MCP load `StrategyConfigStore.load()`.
- **MCP rate limiting (#26)** — 1 concurrent review, 30/hour cap, cancel on stdin close.
- **URLSession redirect Authorization stripping (#25)** — shared delegate across all providers.
- **First notarized DMG** — unblocks `appcast.xml`, website download button, Sparkle.

## Hard-Won Rules (carry these forward)

From `tasks/lessons.md` and memory:

- **Streaming SSE, always.** Non-streaming LLM calls time out. Every provider uses `URLSession.bytes(for:)`.
- **Validate core interactions end-to-end before stacking features.** One provider + one call + streaming response first, then build.
- **Don't enumerate specific MCP clients or AI CLIs.** Say "any MCP client" / "any AI CLI" — Claude Code, Cursor, Warp, Cline, Zed, etc. all just work. Enumeration implicitly excludes the rest.
- **Match the security baseline of the other macOS apps.** Apple Developer ID + notarization + Sparkle. No custom updater, no YubiKey root, no XPC.
- **Don't push back on scope expansion** — the user prefers wider v1 over faster ship. Treat scope additions as decisions, not questions.
- **Don't auto-endorse subagent creative output.** Creative output (taglines, naming, copy, design choices) is relayed as proposals, not recommendations.
- **Every UI change on the app or website must trace back to `docs/DESIGN-SYSTEM.md`.** No hardcoded hexes. No ad-hoc padding. No new tokens without documenting them.

## Files Changed This Session (Reference)

### Website — new files
```
Joint Chiefs Website/
├── styles.css                         (856 lines — extracted from index.html)
├── download.html
├── guide/mcp.html
├── guide/cli.html
├── guide/security.html
├── 404.html
├── sitemap.xml
├── robots.txt
├── appcast.xml
├── og-image.png                       (1200×630)
├── favicon-16.png / favicon-32.png / apple-touch-icon.png
├── llms.txt
├── scripts/make-favicon.swift
├── scripts/make-og-image.swift
└── docs/DESIGN-SYSTEM.md
```

### Website — modified
```
index.html  (inline <style> removed, now links styles.css; Agentdeck tokens; announcement bar; pixel wordmark)
CLAUDE.md   (references docs/DESIGN-SYSTEM.md)
docs/BUILD-PLAN.md, docs/KNOWN-ISSUES.md
```

### App — new files
```
JointChiefs/Sources/JointChiefsSetup/DesignSystem/AgentdeckTokens.swift
JointChiefs/Sources/JointChiefsSetup/DesignSystem/AgentdeckTypography.swift
JointChiefs/Sources/JointChiefsSetup/DesignSystem/AgentdeckButtonStyle.swift
docs/DESIGN-SYSTEM.md
```

### App — modified
```
CLAUDE.md   (references docs/DESIGN-SYSTEM.md, Degree Daddy reference sanitized)
docs/KNOWN-ISSUES.md (setup app token migration items added)
```

## Status At Handoff

- Website: ✅ complete structurally, ❌ not in version control, ❌ not deployed, ❌ mobile not visually verified
- App: ✅ design system scaffold compiles, ❌ views not yet migrated to tokens, ❌ 24+ files uncommitted
- Public repo: ✅ live at `github.com/djfunboy/joint-chiefs`, MIT licensed, history clean
- Deployment: ❌ `jointchiefs.ai` DNS not pointed anywhere; Netlify not configured

If you only have time for one thing next session, it's task #1 above: migrate the setup-app views to use the design system tokens. That's the structural debt that blocks everything else from feeling cohesive.
