# Joint Chiefs — v2 Direction & Security Plan (Revision 2)

**Status:** Draft for second Joint Chiefs review
**Date:** 2026-04-16
**Domain (owned):** jointchiefs.ai
**Supersedes:** `SECURITY-AND-DIRECTION-PLAN.md` (v1, same date)

This revision incorporates the panel's findings from the v1 review (transcript: `tasks/jc-review-result.md`). Every critical, high, and medium finding is addressed below with attribution. Two architectural decisions from v1 were reversed based on the panel's analysis:

- **Dual update path (Sparkle + custom)** → **single custom updater** (panel finding HIGH-5).
- **Keychain access-group sharing** → **XPC service embedded in .app** proxies Keychain reads to CLI/MCP (panel finding HIGH-3 / "highest-probability total product failure at launch").

---

## Part 1 — Strategic Direction

### What v1 was
A CLI-only tool. Phases 1–5 of the original BUILD-PLAN complete. Phases 6–8 deferred.

### What v2 is
A **three-surface product** distributed under MIT license at jointchiefs.ai:

1. **MCP server (`jointchiefs-mcp`)** — primary discovery framing. Stdio-only JSON-RPC server exposing one tool: `joint_chiefs_review`. Spawned by Claude Code, Claude Desktop, Cursor, and other MCP clients.
2. **CLI tool (`jointchiefs`)** — setup, debugging, headless invocation, CI integration, the *only* user-visible update prompt surface for users who never open the app.
3. **macOS setup app (Joint Chiefs.app)** — single-window SwiftUI app. One-shot installer pattern. Hosts the embedded XPC service for Keychain access (see Part 2 — surface 2).

### Distribution model
- **Single signed + notarized DMG** at `https://jointchiefs.ai/download` containing `Joint Chiefs.app` with bundled CLI + MCP binaries in `Contents/Resources/`.
- **Default install location for CLI/MCP: `~/.local/bin/`** (panel finding MED-9). User-writable, no architecture dependency, no Homebrew dependency, no sudo. The app detects whether `~/.local/bin/` is on `$PATH` and prompts the user to add it if not. As a fallback, the app offers Homebrew prefix detection (via `brew --prefix` if available) and an explicit "choose custom path" option. This works on Intel Macs, Apple Silicon, and machines without Homebrew.
- **Single update channel.** No Homebrew formula in v1.

### Auto-update model — single custom updater (revised)

The dual-path design from v1 is dropped. **One updater library** serves all three binaries. Sparkle is removed entirely from the dependency graph. Reasons:

- Two trust pipelines on the highest-risk surface = audit burden a solo project cannot sustain (panel HIGH-5).
- Sparkle's appcast format is a separate trust input from a custom `latest.json`, creating split-brain version semantics and key-rotation logic.
- The CLI updater handles the only update-prompt UX users actually see (since the app is one-shot setup). The GUI rarely matters.

**Updater architecture:**
- `JointChiefsUpdater` library inside `JointChiefsCore` consumed by all three binaries.
- The app, when launched, calls the library on a background thread and surfaces results in the UI.
- The CLI calls the library at startup (interactive TTY → y/n prompt; non-interactive → stderr notice; explicit `jointchiefs update` subcommand for unattended invocation).
- The MCP server calls the library at startup, logs to stderr only.
- For the rename-over-running-binary problem, an external **shim helper** (`jointchiefs-update-helper`, also bundled) performs the final replacement after the calling process has exited.

### Strategy configuration
Same as v1: setup app exposes a Strategy panel (moderator, consensus mode, tiebreaker, max rounds, timeout). Persists to `~/Library/Application Support/Joint Chiefs/strategy.json` (file permissions: user-writable only, group/other no access). CLI flags override per invocation.

---

## Part 2 — Security Plan (revised)

### Threat model

**What we defend against** (unchanged from v1, plus additions):

- Supply chain compromise of the update channel (artifact AND metadata).
- API key exfiltration via storage, logs, error messages, stack traces, process args, or HTTP redirects.
- Downgrade attacks (signed-but-old DMGs, manual installs, reinstall flows).
- Path traversal and symlink attacks on file reads and binary writes.
- Memory/resource DoS via malformed input.
- Process inspection leaks.
- **Compromised signing key (NEW).** Key compromise must not yield indefinite trust in attacker-signed updates. Recovery is a first-class architectural concern, not an operational afterthought.
- **Update suppression and control-plane attacks (NEW, panel HIGH-1).** An attacker who controls the update metadata channel must not be able to pin clients to vulnerable versions, suppress key-rotation announcements, or block emergency updates.
- **Financial abuse via MCP fan-out (NEW, panel HIGH-7).** Misbehaving MCP clients or runaway autonomous agents must not silently generate unbounded LLM API spend.

**What we explicitly do NOT defend against** (clarified from v1):

- Compromised AI providers — code submitted is sent to OpenAI / Anthropic / Google / xAI as a deliberate function. Documented in SECURITY.md and the setup app's first-run screen.
- Malicious local user with shell access as the same user.
- Malicious MCP client (parent process owns stdin/stdout/env by definition). Trusted parent ≠ well-formed input — defenses against malformed input still apply (panel MED-11).
- Prompt injection in returned LLM content (AI client's defense layer).
- Hardware-level attacks and kernel exploits.

### Surface 1 — Auto-update channel (heavily revised — panel CRIT-1, HIGH-1, HIGH-2, HIGH-6)

#### 1a. Two-tier signing key hierarchy (panel CRIT-1)

The single-pinned-key model from v1 is replaced.

- **Root key (long-lived):** Ed25519 keypair generated once. Private key stored on a **hardware token (YubiKey, mandatory — not "probably")**. Used only to sign signing-key certificates. Never used to sign release artifacts directly. Public key is pinned into every shipped binary at build time.
- **Signing keys (short-lived):** Ed25519 keypairs rotated on a forced 90-day schedule (or sooner if compromise suspected). Each signing key is bound to a **certificate** signed by the root key, encoding: signing public key, validity-not-before, validity-not-after, key ID, and serial number.
- **Per-release artifacts** (DMG, signed metadata) are signed with a signing key whose certificate is shipped alongside the artifact.
- **Verification flow on the client:** verify the certificate chain (signing-key cert is signed by pinned root + within validity window + not in revocation list) → verify the artifact signature with the certified signing key.
- **Key compromise recovery:** issue a new release with a fresh signing key certified by the root key (which was never exposed). The compromised signing key's certificate is added to a revocation list distributed in the next signed `latest.json` and consulted before trusting any signing key.
- **Lost root token recovery:** documented in `SECURITY.md` — backup hardware token stored in a separate physical location (safe deposit box) and provisioned at the same time the primary is generated. Loss of both tokens forces a hard re-bootstrap: new pinned root key in a new release, distributed via the website out-of-band, with prominent user-facing communication.
- **Tabletop exercise** documented before launch: full simulation of signing key compromise, token loss, and emergency-release procedures.

#### 1b. Signed update metadata (panel HIGH-1)

`latest.json` is signed and structurally cryptographically bound to the artifact.

```jsonc
{
  "payload": {
    "version": "0.4.0",
    "channel": "stable",
    "artifact_url": "https://jointchiefs.ai/releases/0.4.0/Joint Chiefs.dmg",
    "artifact_sha256": "<hex>",
    "artifact_size_bytes": 12345678,
    "minimum_version": "0.3.2",
    "release_notes_url": "https://jointchiefs.ai/releases/0.4.0",
    "emergency_message": null,
    "signing_key_certificate": "<base64 cert signed by root>",
    "revoked_signing_keys": ["<key id 1>", "<key id 2>"],
    "issued_at": "2026-04-16T19:00:00Z",
    "expires_at": "2026-05-16T19:00:00Z"
  },
  "signature": "<ed25519 sig over payload, by signing key in payload.signing_key_certificate>"
}
```

- The signing-key certificate is included inline. Client verifies cert chain back to pinned root.
- The `payload.signature` covers the entire `payload` object. Client verifies before trusting any field.
- The `expires_at` field bounds replay of stale-but-valid metadata. Client refuses metadata older than `expires_at`.
- The `revoked_signing_keys` list is checked before trusting the included signing-key certificate.
- The 24-hour cache stores the full signed payload. On read, the signature is re-verified — a tampered cache fails verification and triggers a fresh fetch (panel HIGH-1).
- Cache location: `~/Library/Caches/ai.jointchiefs/latest.json` (panel HIGH-1).

#### 1c. Formal updater verification protocol (panel HIGH-2)

The updater follows this exact sequence. Every step has a dedicated test, including negative tests for tampered inputs at each stage.

1. **Fetch** `latest.json` from `https://jointchiefs.ai/latest.json` (HTTPS-only, system trust store, hostname pinned).
2. **Verify signature** on the metadata payload using the signing key from `payload.signing_key_certificate`, after verifying that certificate chains to the pinned root and is not in the local revocation list.
3. **Verify metadata freshness** (`issued_at` ≤ now ≤ `expires_at`).
4. **Compare versions.** If `payload.version` ≤ installed version → no update needed.
5. **Download artifact** to `~/Library/Caches/ai.jointchiefs/downloads/<sha256>.dmg`.
6. **Verify artifact size** matches `payload.artifact_size_bytes`.
7. **Verify artifact SHA-256** matches `payload.artifact_sha256`. This binds the metadata to the actual file.
8. **Verify DMG code signature** via `Security.framework` — `SecStaticCodeCreateWithPath` + `SecStaticCodeCheckValidityWithErrors` with `kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode`. Verify Team ID matches the expected value (Chris Doyle's Apple Developer Team ID, hardcoded into the binary).
9. **Mount DMG.**
10. **Validate payload contents:**
    - Expected bundle: `Joint Chiefs.app` at the DMG root.
    - Expected files inside `Contents/Resources/`: exactly `jointchiefs`, `jointchiefs-mcp`, `jointchiefs-update-helper` (allowlist; reject anything unexpected — panel HIGH-2).
    - Each executable is independently code-signed, validated via `SecStaticCodeCheckValidityWithErrors` with the same Team ID match.
    - Hardened Runtime is enabled on every executable (`kSecCSEnforceHardenedRuntime`).
    - Notarization staple is present and valid (`spctl --assess --type install` equivalent via `SecAssessment`).
11. **Verify `.app` bundle version** matches `payload.version`.
12. **Atomic install:**
    - For the .app: rename current `/Applications/Joint Chiefs.app` to `/Applications/Joint Chiefs.app.old.<timestamp>`, then rename mounted `.app` over `/Applications/Joint Chiefs.app`. On success, remove `.old.<timestamp>`. (If the app is the calling process, defer this step to `jointchiefs-update-helper`.)
    - For each CLI/MCP binary in the install directory: write to `<install_dir>/.<name>.tmp.<pid>`, fsync, rename over the existing path. Order: helper first, then `jointchiefs-mcp`, then `jointchiefs` last (so a crash mid-update leaves a working CLI for diagnosis).
13. **Strip quarantine attribute** (`com.apple.quarantine`) from the installed binaries via `xattr -d`.
14. **Persist updated state** (`~/Library/Application Support/Joint Chiefs/security-state.json`): new installed version, new minimum_version floor, new revocation list.
15. **Unmount DMG.** Delete cached download.

Each step on failure: log a structured error to stderr (no key material, no internal paths), abort the update without modifying installed state, surface a user-facing error message that's actionable.

#### 1d. Anti-rollback and minimum-version policy (panel HIGH-6)

- `payload.minimum_version` is persisted to `~/Library/Application Support/Joint Chiefs/security-state.json` whenever a successfully verified update is applied. Only ever increases.
- On every CLI/MCP/app startup, check installed version against persisted `minimum_version`. If installed version < persisted minimum, refuse to run with a clear error: `"This installation is below the security floor v<X>. Run 'jointchiefs update' or download from https://jointchiefs.ai."`.
- File permissions on `security-state.json`: 0600 (user-writable only).
- **Offline grace period:** if `latest.json` cannot be reached for ≥ 7 days AND the installed version is below a hard-coded "minimum compatible" baseline (compiled in at build time, advanced once per quarter), refuse to run.
- Manual installation of an older DMG is rejected at step 4 of the verification protocol (downgrade rejection on `payload.version` ≤ installed version) AND at startup (security-state minimum check).

### Surface 2 — API key handling (revised — panel HIGH-3)

#### 2a. XPC service for Keychain access (replaces access-group assumption)

The v1 plan assumed signing all three binaries with a shared Keychain access group would yield seamless access. **The panel correctly identified this as wrong** for non-sandboxed binaries. Access groups are an iOS / sandboxed-macOS concept; non-sandboxed macOS binaries use path-based ACLs that break when binaries are replaced during updates.

**Revised architecture:**

- An XPC service named `JointChiefsKeychainAgent` ships inside the `.app` bundle at `Contents/XPCServices/JointChiefsKeychainAgent.xpc`.
- The XPC service is the only process that reads/writes Keychain entries for Joint Chiefs API keys.
- The CLI and MCP server connect to the XPC service via `NSXPCConnection` (using the well-known service name registered by the .app), request a key by provider name, receive the key in memory, drop the connection.
- The XPC service is signed with the same Developer ID as the .app and is launched on demand by `launchd` when a connection is requested.
- Because the XPC service is invoked indirectly via launchd (not spawned by the calling process), it has its own stable identity for Keychain ACL purposes — independent of the binary that's calling it. Updating the CLI/MCP does not invalidate Keychain trust.
- The first time the XPC service is invoked, macOS prompts the user once to authorize Keychain access. The user clicks "Always Allow." Subsequent reads from any caller (CLI, MCP, app) are silent.

#### 2b. Mandatory empirical prototype before any other code (panel HIGH-3, "do not ship without empirical validation")

Before *any* other build work, build a minimal three-binary prototype on a clean macOS install:
- A "setup" target that writes a test Keychain entry via the XPC service.
- A "CLI" target installed at `~/.local/bin/test-jc` that reads the entry via XPC and prints success/failure.
- A "fake MCP server" target invoked by a simulated parent process (a separate test binary that spawns it via `Process` with stdio piped, mimicking how Claude Desktop spawns MCP servers).

**Test matrix:**
- First run after install (fresh Keychain authorization).
- Second run (post-"Always Allow").
- After machine restart.
- After Keychain locked then unlocked.
- After binary replacement (CLI updated in place — does Keychain still trust?).
- MCP server invoked headlessly (no terminal attached) — does the prompt appear silently and fail?

Only after this prototype demonstrates clean behavior across all six scenarios do we commit to the architecture and proceed with the full build. If any scenario fails, rethink before writing more code.

#### 2c. Key handling controls (carried forward from v1, plus additions)

- **`APIKey` value type** wraps the string. No `Codable`, no `CustomStringConvertible`, no `CustomDebugStringConvertible`, no `description` override. Compile-time enforcement.
- **Read at the moment of use, drop reference immediately.** No caching in long-lived structs.
- **Never logged, never in error messages, never in stack traces, never as command-line arguments.** Auth failures surface as "OpenAI authentication failed" with no key prefix.
- **Keyless MCP config snippets.** App's snippet generator produces JSON with no `env` block. MCP server reads keys via XPC from Keychain at invocation.
- **Env vars are CI-only escape hatch.** Documented as such. When set, override Keychain so CI can supply ephemeral keys without touching system Keychain.
- **Keychain accessibility:** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. No iCloud sync. Locked-machine = no access.

#### 2d. Provider egress controls (panel MED-10)

- **Hardcoded provider URL allowlist.** Provider base URLs (`https://api.openai.com`, `https://generativelanguage.googleapis.com`, `https://api.x.ai`, `https://api.anthropic.com`) are compiled into the binary as constants. Not user-configurable. (Ollama is excepted because it's localhost-only.)
- **URLSession redirect handling:** custom `URLSessionDelegate` intercepts `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)`. If the redirect target host differs from the original request host, the Authorization header is stripped from the new request. For authenticated provider calls, redirects to a different host are simply refused (return nil from the delegate to cancel).
- **TLS hostname validation enforced** on all provider connections (URLSession default, but explicitly documented as a non-disable invariant).
- **Centralized redaction utility** (`SecretRedactor`) scrubs known API key prefixes (`sk-`, `sk-ant-`, `gsk_`, `xai-`, `AIza`) from any string passed through. All `Logger` and stderr output paths route through this utility. Test assertions verify redaction triggers on every known prefix.
- **Release-build log level excludes request/response bodies entirely.** Only error metadata is logged; request payloads (which include source code) and response payloads (which may contain reflected keys in error messages from misbehaving providers) are dropped.

### Surface 3 — MCP server (revised — panel HIGH-7, MED-11)

#### 3a. Stdio-only architectural invariant (panel MED-11)

- **Documented in `SECURITY.md`** and as a prominent code comment at the transport initialization point: "The MCP server supports ONLY stdio transport. Network transports (HTTP, SSE, WebSocket) are architecturally prohibited because the entire security model — trust inherited from parent process, no authentication, no authorization, no network exposure — depends on this assumption. Adding a network transport requires a full threat model revision."
- The transport is hardcoded; there is no configuration knob to switch transports.

#### 3b. Input validation (carried from v1)

- Max request size: 1 MB. Larger requests rejected with `request too large` JSON-RPC error.
- Max JSON nesting depth: 32.
- `code` argument bounded separately to 256 KB.
- Per-request timeout: 120s (configurable via the strategy config, but capped at 600s).
- All tool dispatch via static handler map. No `eval`, no dynamic code execution.
- JSON-RPC error responses follow the spec; do not leak stack traces or internal paths.

#### 3c. Rate limiting and financial abuse defense (NEW — panel HIGH-7)

- **Sliding-window rate limits per MCP connection:** default 10 requests/minute, 100/hour. Configurable via strategy config.
- **Concurrency cap:** maximum 3 simultaneous review batches in flight per connection. Additional requests queued.
- **Bounded work queue:** max 10 queued requests. Overflow rejected with `queue full, retry after N seconds` JSON-RPC error.
- **Cancellation propagation:** when stdin closes (parent process died), all in-flight provider calls are cancelled.
- **Optional daily spend cap:** configurable in strategy config. Approximated from per-review token estimates × number of configured providers × known per-token pricing tables. When cap is hit, MCP server returns a `daily spend cap reached` error until the next UTC day boundary. Default off (opt-in for users who want it).
- **Rate-limit metadata in MCP tool description** so the client can adapt its retry behavior.
- **stderr logs** record rate-limit triggers and overflow rejections (no request payloads).

### Surface 4 — CLI file I/O and install path (revised — panel MED-9)

#### 4a. Install path (replaces v1's hardcoded `/opt/homebrew/bin/`)

- **Default install location: `~/.local/bin/`.** User-writable. No architecture, Homebrew, or sudo dependencies.
- **At install time** the setup app:
  1. Detects whether `~/.local/bin/` exists; creates if missing.
  2. Detects whether `~/.local/bin/` is on `$PATH`; if not, prompts the user with the exact line to add to `~/.zshrc` (`export PATH="$HOME/.local/bin:$PATH"`) and offers to append it.
  3. Offers an alternative path option: detected Homebrew prefix (via `brew --prefix` if available) or a custom user-chosen path.
- **Source-build path** (for power users): `swift build -c release && cp .build/release/jointchiefs ~/.local/bin/jointchiefs` documented in README.
- **Symlink handling** (panel MED-9): rather than blanket symlink rejection (which breaks Homebrew semantics), use `realpath()` to resolve, then validate the resolved target is within an expected install directory, owned by the current user, and is a regular file. This permits standard Homebrew symlink layouts while still preventing symlink-based attacks.

#### 4b. File reading for review (carried from v1)

- Path validation: absolute paths only, resolved via realpath, must be within current user's accessible filesystem.
- Size limit: 1 MB per file.
- Symlink resolution: follow once, check the resolved target meets all constraints.
- No special files: reject `/dev/*`, `/proc/*` (defensive), named pipes, sockets.

### Surface 5 — Build, signing, and dependency hygiene (revised — panel HIGH-5)

- **Hardware token mandatory** (not "probably") for the root signing key. YubiKey 5 series or equivalent FIPS-validated device.
- **Backup hardware token** generated at the same time, stored in a separate physical location (safe deposit box). Loss of one does not force key rotation.
- **Dedicated signing machine.** Not a general-use development machine. Signing operations only. Disk encryption enforced. MFA on local account. No services exposed.
- **Audit log:** every build, signing, and release operation appended to a tamper-evident log (e.g., a git repository on a separate machine that the signing machine pushes to with cryptographically chained commits, or an append-only CloudKit container). Includes timestamp, operator, artifact hashes, version, signing key ID.
- **Release authorization process** documented: each release requires the operator to commit a signed manifest of intent (release notes, version, expected hashes) before the signing operation. The manifest is included in the audit log.
- **Single signer** (Chris). Backup token + documented procedure means no second person needs signing access in v1.
- **Independent checksum publication.** Release artifact SHA-256 hashes are published to a separate channel (e.g., GitHub release notes, signed git tag) so users can independently verify a downloaded DMG.
- **Reproducible builds (best-effort):** Xcode and Swift toolchain versions documented per release. Build script in repo. Same source + same toolchain should produce a hash-identical pre-signing artifact.
- **Pinned dependencies.** `Package.resolved` checked into git. Exact versions, not ranges. Dependabot or weekly manual review for CVE alerts.
- **No remote code execution at build time.** No `curl | sh` install steps. SwiftPM dependencies fetched only from pinned URLs over HTTPS.

### Process controls (carried from v1, plus additions)

- **`SECURITY.md`** in repo root: public threat model, vulnerability disclosure process (`security@jointchiefs.ai` once domain-mail is configured, GitHub Security Advisory as fallback), pinned root key fingerprint, signing key rotation policy, build pipeline summary.
- **`security-general` skill run at every phase boundary:** after Keychain prototype, after CLI polish, after Keychain wiring, after MCP server, after setup app, after auto-update channel, before public release.
- **No telemetry. No analytics. No crash reporting service.** Outbound traffic limited to:
  1. Configured LLM provider APIs.
  2. `https://jointchiefs.ai/latest.json` (no unique identifier — no install tracking).
  3. `https://jointchiefs.ai/releases/...` (artifact downloads).
- **CSP / security headers on jointchiefs.ai:** HSTS preload, strict CSP, Subresource Integrity for any external scripts.

### Open questions — resolved (panel feedback informed answers)

The 8 open questions from v1 are answered below. Source: panel review where addressed; my judgment with rationale where panel was silent.

1. **Bundle CLI + MCP inside the .app, or separately downloadable?** **Bundle inside the app.** Single trust chain, single update path, single distribution model. Source-build remains documented for Linux-curious power users (forward-compatible if we ever port).
2. **Is the 256 KB `code` argument limit right?** **Keep at 256 KB for v1.** Document as configurable for power users via the strategy config (with a hard ceiling of 1 MB to bound memory). Real-world generated-file reviews can exceed 256 KB; preserving headroom prevents foot-shooting on minified bundles or generated protobufs.
3. **Is the 1-second `latest.json` fetch timeout too short?** **Yes — increase to 5 seconds.** Slow networks (mobile tether, hotel wifi) routinely exceed 1s for the first request. 5s is a reasonable upper bound for startup latency and dramatically reduces silent skip-the-update-check failures.
4. **Should `jointchiefs update` require sudo?** **Moot.** The default install path is now `~/.local/bin/`, which is user-owned and never requires sudo. If a user explicitly chose a sudo-required install path, the updater detects insufficient permissions and prints a clear error with the recovery command. No sudo escalation from within the CLI.
5. **Dual update path or single?** **Single (panel HIGH-5).** Sparkle removed. One updater library serves all three binaries. The architectural reversal is documented in this revision's preamble.
6. **Strategy config in JSON file or Keychain?** **Plain JSON file** at `~/Library/Application Support/Joint Chiefs/strategy.json`, file mode 0600. Strategy is non-secret user preference. JSON is readable, debuggable, and survives backup/restore.
7. **MCP update notification: tool response or stderr?** **stderr only for v1.** Keeps tool output clean. If users complain that stderr from MCP servers is invisible to them (likely, given how AI clients hide that), promote to a structured `update_available` field in the tool response in v0.2.
8. **Per-provider opt-in for "code is sent to provider X" disclosure?** **Documentation only, not a technical control.** Per-provider opt-in is paternalistic, easily circumvented (users will just enable everything to make it work), and creates a false sense of security. Honest disclosure in `SECURITY.md`, the README, and the setup app's first-run screen is the right surface. The setup app's provider list shows each provider's data-handling policy URL inline.

### Findings status table

| Finding | Severity | Status |
|---|---|---|
| No signing key compromise recovery mechanism | CRITICAL | Resolved — two-tier hierarchy with hardware-token root + short-lived signing keys + revocation |
| Unsigned latest.json metadata | HIGH | Resolved — signed payload schema with cert chain, hash binding, expiry |
| Updater trust flow underspecified | HIGH | Resolved — formal 15-step verification protocol with negative tests required |
| Keychain access-group assumption likely wrong | HIGH | Resolved — XPC service inside .app proxies Keychain access; mandatory prototype before further code |
| Dual update paths split-brain | HIGH | Resolved — single custom updater, Sparkle removed |
| Build pipeline controls insufficient | HIGH | Resolved — mandatory hardware token, audit log, release authorization process, dedicated signing machine |
| Downgrade protection incomplete | HIGH | Resolved — signed minimum_version field, persisted client-side, hard refusal below floor, offline grace period |
| No MCP rate limiting / financial abuse risk | HIGH | Resolved — sliding-window limits, concurrency cap, bounded queue, cancellation, optional spend cap |
| Hardcoded /opt/homebrew/bin breaks Intel + Homebrew semantics | MEDIUM | Resolved — default ~/.local/bin, Homebrew detection, custom path option, realpath-based symlink validation |
| Provider egress controls underspecified | MEDIUM | Resolved — URL allowlist, redirect Authorization stripping, centralized redaction utility, release-build log scope |
| MCP transport invariant not documented | MEDIUM | Resolved — stdio-only documented in SECURITY.md and at transport init point |

### Open questions for the second review

These remain genuinely open and the panel should weigh in:

1. **Is the XPC service architecture for Keychain access correct, or is there a simpler mechanism we're missing?** Chris's other apps use `KeychainService` directly — none of them have the multi-binary deployment problem we have. Specifically: does anyone know a reference implementation of an XPC service shared between an app and CLIs distributed in the same DMG that we can borrow?

2. **Is 5 seconds the right `latest.json` fetch timeout, or should it be higher?** Trades startup latency for reliability on slow networks. The MCP server in particular wants to start fast since it's blocking the AI client's first tool call.

3. **For the offline grace period (7 days before hard block), is that humane enough for users on travel / intermittent connectivity?** Could be 14 or 30 days. But longer = more time a known-vulnerable client keeps running.

4. **Should we publish release artifact hashes to a transparency log** (e.g., Sigstore) **in addition to GitHub release notes?** Adds complexity but provides cryptographic transparency for security researchers.

5. **For the MCP rate-limit defaults (10/min, 100/hour), are those right for typical Claude Code usage?** Hard to know without telemetry (which we don't have). Erring toward generous; users with autonomous agents may need to lower them.

6. **Is the `jointchiefs-update-helper` shim binary a third trust target that needs its own signing review?** It performs file replacement on the running app. Yes — it's in the verification-protocol allowlist. Worth confirming the panel agrees this is sufficient.

---

## Review goal (second pass)

Confirm whether the v1 findings are adequately addressed. Specifically:

- Are the threat model additions (signing key compromise, update suppression, financial abuse) framed correctly, or are there sub-cases missed?
- Does the two-tier key hierarchy actually solve the trust-root problem, or is there a subtler attack against the certificate chain itself?
- Is the formal updater verification protocol complete, or are there missed steps (TOCTOU windows, atomic-rename edge cases on different filesystems, app-bundle codesign invalidation during partial replacement)?
- Does the XPC service architecture survive scrutiny, especially for the headless MCP server case?
- Are the rate-limit defaults sane, or off by an order of magnitude?
- Are there new findings introduced by the revisions themselves?
- Address each of the 6 open questions at the end with a clear position.

Severity guidance same as v1.
