# Security Policy

Joint Chiefs is a macOS app that sends source code to external LLM APIs and stores API keys on disk. This document covers the threat model, the design choices that flow from it, and how to report issues.

## Scope

**In scope.** Anything that could leak API keys, expose submitted code to unintended third parties, allow remote code execution on the user's machine, or let a remote attacker read the user's stored keys.

**Out of scope.** The behavior of the LLM providers themselves (OpenAI, Google, xAI, Anthropic, local Ollama). When you submit code through Joint Chiefs, it is sent to whichever providers you've configured. Their data-handling policies apply from the moment your code leaves your machine. Joint Chiefs does not and cannot guarantee how providers use submitted content.

## Key storage

API keys are stored in a permission-locked file: `~/Library/Application Support/Joint Chiefs/credentials.json`, written with mode `0600` (readable and writable only by the owning user) in a directory set to `0700`. Keys are never logged, and never leave the machine except as the Authorization header of an HTTPS request to the provider you configured.

This is the standard server-side credential pattern, chosen because Joint Chiefs has to work headless — invoked over SSH or from cron, with no logged-in GUI user. Earlier versions used the macOS Keychain; its access approval is an interactive GUI prompt that a headless session cannot show or answer, so the CLI and MCP server could not read saved keys. A `0600` file has no session or prompt dependency. On a Mac with FileVault enabled — Apple's default on modern hardware — the file is encrypted at rest along with the rest of the disk.

**Honest threat model.** A `0600` file protects the keys from *other* local user accounts and from any remote attacker who cannot already run code as your user. It does *not* protect against an attacker who is already executing as your user account, and on a Mac *without* FileVault it does not protect against someone with physical access to the disk. This is the same exposure as an SSH private key, an AWS credentials file, or a `.npmrc` token — and the same exposure the environment-variable path always had. If you handle keys that warrant stronger isolation, enable FileVault and treat the machine's user account as the trust boundary.

One binary — `jointchiefs-keygetter` — is the only process that reads or writes the credentials file. Every other Joint Chiefs surface (CLI, MCP server, setup app) shells out to it via `Process` and discards the key as soon as the provider call completes, so the file's access path is auditable in exactly one place. Joint Chiefs v0.5.6 and earlier stored keys in the Keychain; on first launch the setup app runs a one-time migration (`jointchiefs-keygetter migrate`) that moves any legacy Keychain keys into the file and removes the Keychain items.

An environment-variable fallback exists (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.) for CI contexts. It takes precedence over the credentials file when set. This path is documented as CI-only in the setup app's first-run disclosure. End users should not set these variables.

## MCP server

The MCP server (`jointchiefs-mcp`) is stdio-only. Network transports — HTTP, Server-Sent Events, WebSocket — are architecturally prohibited. Every security assumption in the product depends on the MCP client owning the server's stdio by definition: the client is a process on the same machine that spawns the server as a child, passes messages via pipes, and reaps it on exit. There is no port bound, no socket listening, no inbound network surface.

Rate limits apply per invocation: one concurrent review per client, thirty reviews per hour, automatic cancellation when stdin closes. These protect against a compromised or misbehaving MCP client exhausting provider quotas or leaking cost.

## Code sent for review

Source code submitted to Joint Chiefs is sent to every provider you've enabled for the current review. It is written to a local transcript file (one per review) so you can reread the debate. Transcripts live on your machine only — they are not synced, uploaded, or backed up by Joint Chiefs. You can delete them at any time.

Joint Chiefs does not cache provider responses beyond the transcript. It does not telemeter. It does not connect to any server except the provider endpoints you configured.

## Code signing and updates

Release binaries are signed with an Apple Developer ID Application certificate and notarized through Apple's notary service. The DMG is also signed, notarized, and stapled so Gatekeeper accepts it without a network round-trip on first launch. Updates are delivered via Sparkle; the appcast is served from jointchiefs.ai over HTTPS, and every release item carries an EdDSA signature that Sparkle verifies before installing. A tampered appcast or DMG fails the EdDSA check and is rejected.

No custom updater exists. No YubiKey root of trust. No XPC service. The surface is deliberately the same as every other Developer-ID-signed Mac app.

## Reporting a vulnerability

Please open a private Security Advisory via GitHub:

https://github.com/djfunboy/joint-chiefs/security/advisories/new

If that isn't accessible, email `chris@sitecapture.com` with "Joint Chiefs security" in the subject line. We acknowledge reports within 48 hours. There is no bug bounty — this is a free, open-source, solo-maintained project — but credit in the release notes is offered for responsible disclosure.

Please do not file public GitHub issues for vulnerabilities. Please do not post findings to social media before the issue is resolved.

## Not-a-promise

Joint Chiefs is provided as-is under the MIT license. The threat model above describes design intent, not warranty. Users handling sensitive code should review the security model against their own risk tolerance before adopting.
