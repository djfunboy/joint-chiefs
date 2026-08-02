# ADR-003: Use the standard Apple distribution baseline

- **Status:** Accepted
- **Decision date:** 2026-04-18

## Context

Earlier security studies proposed a custom updater, hardware-token trust hierarchy, XPC credential service, and dedicated signing infrastructure. Those mechanisms added a second security product to a single-owner developer tool and exceeded the risk profile of the shipping application.

## Decision

Use Apple Developer ID signing, notarization, stapling, and Sparkle for application updates. Sign by the certificate SHA-1 hash, distribute one DMG, and re-install the bundled CLI/MCP/keygetter binaries from the updated app. Do not add a custom updater, XPC service, YubiKey root hierarchy, or bespoke transparency system.

## Consequences

- Release security follows the same maintained platform path as the rest of the portfolio.
- The manual release runbook remains a hard gate and includes a cold-machine smoke test.
- The historical security-direction plans remain reference evidence, not current architecture.
