# Bug Reports — Joint Chiefs

Concrete bugs and their resolutions — the permanent ledger. Open bugs at top; resolved history below (newest first). Theoretical / watch-later items live in [KNOWN-ISSUES.md](./KNOWN-ISSUES.md).

## Open

**No pre-flight validation when picking a moderator without a saved API key**

**Status:** Open

`RolesWeightsView` lets the user select any provider as moderator regardless of whether that provider's key is saved. Save accepts it and the review blows up at runtime.

**Fix:** inline error in `RolesWeightsView.moderatorSection` when `model.keyStatuses[selection]` is `.unconfigured`/`.none`/`.failed`, or disable Save until resolved.

**Discovered:** 04-23 UX review; verified still open against `RolesWeightsView.swift` on 2026-04-26.

## Resolved
