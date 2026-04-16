# Joint Chiefs — Known Issues

**Last Updated:** 2026-04-16

A running list of known bugs, limitations, and rough edges. PRs that fix any of these are welcome.

## Active Bugs

_None currently tracked — file an issue if you hit something._

## Known Limitations

- **Streaming task is not cancelled on early termination.** `runReviewStreaming` creates an unstructured `Task` inside the `AsyncStream` but doesn't wire `continuation.onTermination` to cancel it when the consumer stops iterating. Long debates keep running in the background after a CLI Ctrl-C.
- **Duplicate orchestration paths.** `runReview` and `runReviewStreaming` implement substantially the same workflow in parallel. Bug fixes need to be applied to both.
- **No validation on `debateRounds`.** `DebateOrchestrator.init` accepts negative values without complaint.
- **Empty debate rounds silently continue.** If every provider fails in a single round, the orchestrator records an empty round and keeps going instead of breaking.
- **Convergence detection is title-similarity based.** The adaptive early-break heuristic compares finding titles across rounds. It may stop debate too early when models phrase the same finding differently, or too late when they word the same surface issue identically but disagree on substance.

## Roadmap-Adjacent

These were raised by Joint Chiefs reviewing its own source and remain open:

- Provider attribution can be lost in the non-streaming error path.
- Logger subsystem is hardcoded, which limits reuse if `JointChiefsCore` is embedded in another app.
- `ReviewProvider` existential is passed across `TaskGroup` boundaries without explicit `Sendable` annotation.

## QA Areas Needing More Coverage

Manual verification gaps (automated tests cover the unit and orchestrator layers, but these need real-world runs):

- [ ] Adaptive early-break behavior with all 5 providers under load.
- [ ] Hub-and-spoke moderator synthesis quality on large diffs (>1000 lines).
- [ ] Keychain storage with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` across reboots.
- [ ] CLI behavior when no API keys are configured (should print a clear error).
- [ ] CLI behavior when only one provider is configured (should still produce useful output).
