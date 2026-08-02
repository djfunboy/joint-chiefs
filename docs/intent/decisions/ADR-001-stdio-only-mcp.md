# ADR-001: Keep MCP transport stdio-only

- **Status:** Accepted
- **Decision date:** 2026-04-18

## Context

Joint Chiefs needs a universal integration surface without adding an unauthenticated local network service, port lifecycle, or another process manager. The MCP client already owns a spawned server's stdin, stdout, environment, and lifetime.

## Decision

`jointchiefs-mcp` supports stdio transport only. HTTP, SSE, WebSocket, and other network transports are prohibited unless the security model is redesigned and approved. The CLI invokes the orchestrator directly; the deferred localhost server is not part of the shipping architecture.

## Consequences

- There is no inbound network listener or transport-authentication layer.
- MCP lifecycle and trust inherit from the spawning client.
- Cross-process cases that cannot use stdio or the CLI require a new architecture decision.
