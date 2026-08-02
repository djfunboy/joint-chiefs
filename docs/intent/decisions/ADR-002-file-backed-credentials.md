# ADR-002: Use a permission-locked credential file for headless access

- **Status:** Accepted
- **Decision date:** 2026-05-17

## Context

The macOS Keychain can require an interactive approval prompt. Headless CLI and MCP invocations over SSH, cron, or a session without a logged-in GUI user cannot answer that prompt, so saved credentials become unavailable in the product's primary operating contexts.

## Decision

Store provider keys in `~/Library/Application Support/Joint Chiefs/credentials.json`, mode `0600`, under a `0700` directory. Only `jointchiefs-keygetter` reads or writes the file; the CLI, MCP server, and setup app invoke the keygetter. Retain `LegacyKeychainStore` only for one-time migration from older releases.

## Consequences

- Credential access works without a GUI session or Keychain prompt.
- FileVault and the macOS user account define encryption-at-rest and local trust boundaries.
- A process already running as the user can read the file, matching the documented threat model for SSH keys and other user-scoped credential files.
