# Status — Joint Chiefs

**State snapshot. Replace this file, do not append to it.** Durable plan and sequence
live in [`docs/intent/ROADMAP.md`](../docs/intent/ROADMAP.md).

Snapshot source: the dissolved `BUILD-PLAN.md`, checked against the v0.5.13 tag,
current appcast, CLAUDE.md, and shipping source during the docs migration.

## Shipping baseline

- Latest release: v0.5.13, CFBundleVersion `1777000011`.
- Shipping surfaces: CLI, stdio MCP server, macOS setup app, and credential-file keygetter.
- Six provider types, moderator-led hub-and-spoke debate, adaptive convergence, four consensus modes, provider weighting, and per-provider model overrides are implemented.
- Signed/notarized DMG, Sparkle appcast, public MIT app repository, and private auto-deployed website repository are live.
- The automated suite contains 90+ tests; `swift test` is authoritative for the current count.

## Phase state

| Phase | State |
|---|---|
| 1 — Scaffold and provider protocol | Complete |
| 2 — Provider panel | Complete |
| 3 — Debate orchestrator | Complete |
| 4 — Local HTTP server | Deferred; stdio MCP and direct CLI invocation are the accepted architecture |
| 5 — CLI | Complete |
| 6 — Setup app | Complete baseline; accessibility and migration smoke testing remain (moderator-key preflight landed 2026-08-02, unreleased) |
| 7 — Transcript viewer | Deferred |
| 8 — MCP server | Complete |
| 9 — Polish and testing | Partial |
| 10 — Security and distribution | Complete baseline |

## Active verification and product gaps

- Moderator/tiebreaker key pre-flight landed 2026-08-02 (unreleased) — the bug ledger has no open entries. See [`BUG-REPORTS.md`](../docs/as-built/BUG-REPORTS.md).
- Complete VoiceOver and Dynamic Type smoke testing across the five setup sections.
- Profile idle memory and end-to-end review latency.
- Run the real legacy-Keychain migration and headless credential-read test matrix.
- Validate six-provider adaptive convergence and moderator quality on large diffs.
- Automatic related-file, git-diff, and project-doc context remains unimplemented.

## Non-urgent follow-ups

Carried forward from the April session notes when those were retired.

- **Homebrew tap** — `djfunboy/homebrew-jointchiefs` does not exist yet, so the cask
  still lives at `Casks/joint-chiefs.rb` in this repo. Creating the tap and copying the
  cask in is what unlocks `brew install --cask joint-chiefs`.
- **Netlify site ID in the public repo** — it appears in `docs/as-built/ARCHITECTURE.md`.
  Not a credential, low priority, but this repo is public.
- **Automate the Dropbox xattr workaround in `scripts/build-app.sh`** — Dropbox attaches
  `com.apple.FinderInfo` to bundles and breaks codesign; staging to `/tmp` before signing
  is currently manual. FiftyX's `scripts/release.sh` already does this automatically and
  is the pattern to copy.
