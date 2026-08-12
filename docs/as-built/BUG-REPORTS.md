# Bug Reports — Joint Chiefs

Concrete bugs and their resolutions — the permanent ledger. Open bugs at top; resolved history below (newest first). Theoretical / watch-later items live in [KNOWN-ISSUES.md](./KNOWN-ISSUES.md).

## Open

_None._

## Resolved

**No pre-flight validation when picking a moderator without a saved API key**

**Status:** Resolved 2026-08-02 — unreleased; ships in the next release.

`RolesWeightsView` let the user select any provider as moderator regardless of whether that provider's key was saved. Save accepted it and the review blew up at runtime. The tiebreaker picker had the same defect.

**Fix:** `StrategyConfig.roleKeyIssues(configuredProviders:)` in `JointChiefsCore` reports any role assigned to a provider with no usable key. `SetupModel.roleKeyIssues` feeds it from the credential probe (suppressed until `keyStatusesProbed` flips, so a configured install never flashes a false warning at first paint). `RolesWeightsView` renders an inline error under the affected picker and disables Save while any issue stands; `saveStrategy()` also throws `StrategySaveError.roleKeyMissing` so the invariant does not depend on button state. Covered by `RoleKeyPreflightTests` (10 tests).

**Discovered:** 04-23 UX review; verified still open against `RolesWeightsView.swift` on 2026-04-26.
