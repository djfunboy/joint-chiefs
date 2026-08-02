# Joint Chiefs — v2 Direction & Security Plan

**Status:** Draft for Joint Chiefs review
**Date:** 2026-04-16
**Domain (owned):** jointchiefs.ai

This document captures the architectural direction and security plan for Joint Chiefs v2 — the public open-source release. It is intentionally comprehensive so the review panel has enough surface to find real weaknesses. Pushback is welcome and expected.

---

## Part 1 — Strategic Direction

### What v1 was
A CLI-only tool (`jointchiefs review <file>`) that fans code out to OpenAI / Gemini / Grok / Claude / Ollama in parallel, runs hub-and-spoke debate rounds with Claude as moderator, and prints a consensus summary. Phases 1–5 complete. Phases 6–8 (menu bar app, transcript viewer, MCP wrapper) deferred.

### What v2 is
A **three-surface product** distributed under MIT license at jointchiefs.ai:

1. **MCP server (`jointchiefs-mcp`)** — primary discovery framing for 2026. Stdio JSON-RPC server exposing a single `joint_chiefs_review` tool. Spawned by Claude Code, Claude Desktop, Cursor, and other MCP clients.

2. **CLI tool (`jointchiefs`)** — for setup, debugging, headless invocation, CI integration, and any context that benefits from terminal-native interaction. Crucially, the CLI is also the *setup verification surface* — it's where users confirm keys work (`jointchiefs models --test`) and where update prompts surface (`jointchiefs review` prints "Update available" and prompts y/n).

3. **macOS setup app (Joint Chiefs.app)** — single-window SwiftUI app. One-shot installer pattern: open after download, enter API keys with live test buttons (green ✓ / red ✗), choose debate strategy, generate keyless MCP config snippets to paste into AI client configs, install bundled CLI/MCP binaries to `/opt/homebrew/bin/`. Closed and never reopened unless rotating keys or applying an update.

### Why MCP-first framing
"MCP server" is the discovery category in 2026. Repos framed as MCP servers get materially more attention on Hacker News, the MCP directory, and the broader AI tools ecosystem than CLIs that do the same thing. The CLI is not de-emphasized — it's the foundation — but the README, website, and product positioning lead with the MCP framing.

### Why all three surfaces
- The CLI alone has high setup friction (env vars, no validation, hidden provider menu, silent bad keys).
- The MCP server alone makes onboarding worse (errors buried in AI-client conversations, slow iteration loop, no clear test surface).
- The app alone duplicates work and limits scriptability.
- Together: app handles friction-free setup, CLI handles verification + headless use, MCP handles in-AI-client invocation. Each surface plays to its native strength.

### Distribution model
- **Single DMG** at jointchiefs.ai/download (Joint Chiefs.app contains bundled CLI + MCP binaries in `Contents/Resources/`).
- **Signed + notarized** with Chris Doyle's existing Apple Developer ID (same one used for Stash, Remind, Degree Daddy, Dance Party).
- **App-first install:** drag .app to /Applications, launch, app's "Install Command-Line Tools" button copies bundled binaries to /opt/homebrew/bin/.
- **Source build path** also documented in README for power users (`swift build -c release`).
- **No Homebrew formula in v1.** Revisit if there's demand. Direct DMG download keeps the install canonical and the update channel single.

### Auto-update model
Two paths sharing one EdDSA signing key:

- **Sparkle** for the app's own updates (when a user does open the app — rare, but covered).
- **Custom CLI/MCP updater:** CLI checks `https://jointchiefs.ai/latest.json` on startup (1s timeout, cached 24h, `JOINTCHIEFS_NO_UPDATE_CHECK=1` opts out). If a newer version exists AND the CLI is running in an interactive TTY, prompts: `"Update available v0.3 → v0.4. Update now? [Y/n]"`. On Y: downloads DMG, verifies EdDSA signature against pinned public key, mounts, atomically replaces app + CLI + MCP binaries, unmounts. On N: skipped until next 24h check window. Non-interactive contexts (pipe, MCP, CI) print stderr notice only — no prompt.
- **Drift prevention:** when Sparkle updates the app, the app on next launch automatically syncs its bundled CLI/MCP binaries to `/opt/homebrew/bin/` (no manual re-click of "Install Command-Line Tools"). Symmetrically, the CLI updater replaces app + binaries in one atomic operation. Both paths land at synced versions across all three surfaces.
- **Explicit `jointchiefs update` subcommand** for non-interactive update (CI, scripted environments).

### Debate strategy configuration
The setup app exposes a Strategy panel:
- **Moderator selection** — which configured provider plays the deciding role (default: Claude).
- **Consensus mode** — `strict` (only findings raised by majority), `moderator's call` (current behavior, moderator decides), `best-of-all` (every finding included), `voting threshold` (configurable %).
- **Tiebreaker** — designated provider that breaks deadlock if convergence isn't reached after max rounds (default: same as moderator).
- **Max debate rounds** — default 5.
- **Per-provider timeout** — default 120s.

These persist to `~/Library/Application Support/Joint Chiefs/strategy.json` (non-secret config; not Keychain). CLI and MCP read this file at startup. CLI flags override file config per invocation.

---

## Part 2 — Security Plan

### Threat model

**What we defend against:**

- **Supply chain compromise of the update channel.** A malicious DMG signed by an attacker, served over a hijacked DNS, or replacing our hosted artifact must not install on a user's machine.
- **API key exfiltration.** Keys never leave Keychain except into outbound API calls to the configured provider. Never to disk in plaintext, never to logs, never in error messages, never in stack traces.
- **Downgrade attacks.** A signed-but-old DMG (e.g., one with a known vulnerability) cannot replace a newer install.
- **Path traversal and symlink attacks.** Reading source files for review and writing to `/opt/homebrew/bin/` during update both validate paths and reject symlinks targeting outside expected directories.
- **Memory/resource DoS via malformed input.** MCP server bounds payload size, JSON nesting depth, and per-request timeout. CLI bounds source-file size.
- **Process inspection leaks.** API keys never passed as command-line arguments (visible via `ps`); environment variables only used as a documented CI escape hatch.

**What we explicitly do NOT defend against:**

- **Compromised AI providers.** Code submitted for review is sent to OpenAI / Anthropic / Google / xAI as a deliberate function of the product. Users who don't trust those providers' data handling policies should not enable those providers. This is documented in SECURITY.md, README, and the setup app's first-run screen.
- **Malicious local user with shell access.** If an attacker has shell as the same user, they can inspect process memory, dump Keychain (with user's permission), or read any user-readable file. Standard threat model — Keychain protects against background processes and other users, not against a fully compromised account.
- **Malicious MCP client.** Whatever process spawned the MCP server (Claude Code, Cursor, etc.) is the parent process — it owns the MCP server's stdin/stdout/environment by definition. We trust the MCP client's identity at spawn time.
- **Malicious provider responses leveraged for prompt injection.** LLM responses are returned to the AI client (Claude). We don't sanitize against prompt injection attempts in returned content — that's the AI client's defense layer.
- **Hardware-level attacks** (cold boot, JTAG, etc.) and **kernel exploits** are out of scope.

### High-stakes surface 1 — Auto-update channel

This is the worst-case attack surface: a single compromise installs malicious code on every user simultaneously. Controls:

- **Pinned EdDSA public key** compiled into every binary (CLI, MCP, app) at build time. Never fetched at runtime. Same key Sparkle verifies against. Key rotation requires a new release with the new key embedded, signed by the old key — trust-on-first-install with explicit migration flow.
- **Signature verification before file replacement.** Download DMG to a temp file → verify EdDSA signature → only then mount and copy. Never partial-trust a downloaded artifact.
- **Downgrade rejection.** The pinned binary embeds its own version. Refuses to replace itself with anything ≤ current version.
- **HTTPS-only with system trust store.** No HTTP fallback. No pinned cert (would block legitimate cert rotation), but verify hostname matches `jointchiefs.ai`.
- **Atomic file replacement.** Write new binary to temp file in same volume, `rename(2)` over the existing path. Interrupted updates leave the old binary intact — no half-replaced state.
- **Symlink rejection on writes.** Before writing to `/opt/homebrew/bin/jointchiefs`, verify target is a regular file owned by current user. Refuse if it's a symlink, owned by another user, or has unexpected permissions.
- **No code execution from downloaded payload before signature verification.** No "extract installer and run" pattern. Just file replacement.
- **Update prompt requires explicit user consent in interactive contexts.** Never silent auto-update except via explicit `jointchiefs update --yes` invocation.

### High-stakes surface 2 — API key handling

Hands-off principle: Joint Chiefs never *holds* keys longer than the moment of a single API call. Controls:

- **Keychain only for storage.** `KeychainService` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so keys don't sync to iCloud and aren't accessible while the machine is locked. No backup, no plaintext config file, no writing to env files we control.
- **Env vars are a CI-only escape hatch.** Documented in README under "CI / Headless" section, not the primary install path. When env var is set, it overrides Keychain (so CI can supply ephemeral keys without touching Keychain).
- **`APIKey` value type** wraps the string. No `Codable`, no `CustomStringConvertible`, no `CustomDebugStringConvertible`, no `description` override. Serialization attempts produce a compile error. Stack traces and debug output cannot accidentally include the key.
- **Keys read at the moment of use.** Read from Keychain → pass to URL request → drop reference. Not cached in long-lived structs (no `@Observable` `var apiKey: String` on services).
- **Never logged, never in error messages.** Auth failure surfaces as `"OpenAI authentication failed — re-enter key in Joint Chiefs.app"`. The string `sk-…` (or any prefix) never appears in our logs, our errors, or our crash reports.
- **Never as command-line arguments.** `ps -ef` must not reveal keys. URLs in `URLRequest` use header authentication, not query parameters.
- **Keyless MCP config snippets.** The setup app's "MCP config" generator produces JSON with no `env` block. The MCP server reads keys from Keychain at invocation. Keys never land in `~/.claude/mcp_servers.json` or any client config file.
- **All three binaries signed with same Developer ID + same Keychain access group entitlement.** macOS treats them as a unit — one user-granted "Always Allow" prompt covers app, CLI, and MCP. Avoids triggering a Keychain prompt mid-Claude-conversation.

### High-stakes surface 3 — MCP server input validation

stdio JSON-RPC parses untrusted input from whatever client spawned the server. Controls:

- **Max request size: 1 MB.** Larger requests are rejected with a `request too large` error. Source code review legitimately needs more headroom; `code` argument bounded separately to **256 KB** (large enough for any single file under review, small enough to reject DoS).
- **Max JSON nesting depth: 32.** Deeply nested objects rejected to prevent stack overflow in the parser.
- **Per-request timeout matches CLI default (120s).** Long-running requests don't pin server resources indefinitely.
- **No `eval`, no dynamic code execution.** All tool dispatch is via static handler map.
- **stderr only for logging.** Never log request contents or response contents — could include source code or keys (the server reads keys mid-request).
- **JSON-RPC error responses follow the spec.** Don't leak stack traces or internal paths in error messages returned to the client.

### High-stakes surface 4 — CLI file I/O and `/opt/homebrew/bin` writes

Reading source files for review:
- **Path validation:** absolute paths only, resolved via realpath, must be within current user's accessible filesystem.
- **Size limit: 1 MB per file.** Same as MCP server bound. Larger files prompt the user to chunk.
- **Symlink resolution:** follow once, then check the resolved target meets the same constraints.
- **No special files:** reject `/dev/*`, `/proc/*` (irrelevant on macOS but defensive), and named pipes / sockets.

Writing to `/opt/homebrew/bin/` during update:
- **Pre-check ownership:** target path must be owned by current user. Refuse if root-owned or owned by another user.
- **Pre-check type:** target must be a regular file or not exist. Refuse if symlink, directory, or special file.
- **Atomic rename within same filesystem.** Write to `/opt/homebrew/bin/.jointchiefs.tmp.PID`, fsync, rename over the existing path.

### High-stakes surface 5 — Build, signing, and dependency hygiene

- **Pinned dependencies.** `Package.resolved` checked into git. Exact versions, not version ranges. Dependabot or equivalent for CVE alerts.
- **Reproducible builds (best-effort).** Document the exact Xcode + Swift toolchain version used to produce the public DMG. Build script in repo. Anyone can rebuild from source and compare hashes (within signing/notarization noise).
- **No remote code execution at build time.** No `curl | sh` install steps in build scripts. Dependencies fetched only via SwiftPM from pinned URLs.
- **Notarization staple verified before release.** `xcrun stapler validate` on the .app and DMG before upload to jointchiefs.ai.
- **EdDSA signing key stored offline.** Not on the build machine in plaintext. Probably on a hardware token (YubiKey) or in macOS Keychain on a dedicated signing machine. Lost-key recovery plan documented.

### Process controls

- **`SECURITY.md` in repo root.** Public-facing threat model + vulnerability disclosure process. Reports go to a dedicated email address (chris@? or security@jointchiefs.ai once domain is configured) or a GitHub Security Advisory.
- **`security-general` skill run at every phase boundary.** Not a one-shot at the end. Run after CLI polish, after Keychain wiring, after MCP server, after setup app, after auto-update channel, before public release. Each run's findings recorded in `tasks/lessons.md`.
- **No telemetry.** No analytics. No crash reporting service. The only outbound traffic is to configured LLM APIs, the update check (`jointchiefs.ai/latest.json`), and the update download (`jointchiefs.ai/releases/...`). Update check sends no unique identifier — no install tracking.
- **CSP / security headers on jointchiefs.ai.** Standard web hardening. The download page must serve over HTTPS with HSTS preload.

### Open questions for the panel

These are the architectural decisions I'm least confident about. Direct disagreement is welcome.

1. **Is bundling CLI + MCP inside the .app the right distribution model**, or should they be separately downloadable for users who don't want a GUI? Trade-off: simplicity / single-source-of-truth vs. flexibility for Linux-curious users (Joint Chiefs is macOS-only today, so this is a hypothetical).

2. **Is the `code` argument limit of 256 KB right?** Real-world code reviews of large generated files (e.g., minified JS, generated protobufs) might exceed this. But raising the limit raises memory pressure on the MCP server.

3. **Is the 1-second timeout on `latest.json` fetch too short?** Slow networks would skip the update check entirely. But long timeouts add startup latency to every CLI invocation.

4. **Should the `jointchiefs update` flow require sudo for `/opt/homebrew/bin/` writes?** On Apple Silicon, that path is user-writable by default for the homebrew owner. But on multi-user setups or unusual configurations it might not be. We can detect and prompt for sudo, but it adds complexity.

5. **Is the dual update path (Sparkle + custom updater) materially better than a single custom updater that the app also uses?** Sparkle is battle-tested but adds a framework dependency, an appcast format to maintain, and a second code path with different failure modes. Reasonable people could pick the single-updater simplification.

6. **Strategy config persisting to `~/Library/Application Support/Joint Chiefs/strategy.json` — should it be in Keychain instead?** Strategy isn't secret per se, but it's user preference. Storing in plain JSON is conventional but means another file to back up / sync / accidentally commit if someone's homedir is in a git repo.

7. **Should the MCP server include the update notification in tool responses** (visible to the user via Claude), **or only in stderr** (mostly invisible)? Visibility argues for in-response; clean tool output argues for stderr-only.

8. **Is documenting "compromised AI providers are out of scope" sufficient**, or do we need an actual technical control (e.g., a per-provider toggle that defaults to off, requiring explicit opt-in)? The first is honest; the second is paternalistic but safer for users who don't read SECURITY.md.

---

## Review goal

The Joint Chiefs panel should evaluate this plan and report:

- **Threat model gaps** — attacks we don't defend against but should
- **Missing security controls** — specific controls not listed that are standard for this class of product
- **Architectural risks** — distribution, update channel, key handling, MCP design
- **UX problems** — onboarding flow, error surfaces, update prompts, Keychain prompts
- **Anything else** that should change before we commit code

Severity guidance:
- **Critical:** would compromise user keys, allow remote code execution, or break the update channel's trust root.
- **High:** weakens a defended boundary, creates a likely future incident, or makes onboarding fail for typical users.
- **Medium:** suboptimal but not exploitable; would cause friction or maintenance burden.
- **Low:** nice-to-have, polish, naming.
