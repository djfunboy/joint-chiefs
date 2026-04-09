# Joint Chiefs — Known Issues

**Last Updated:** 2026-04-09

## Active Bugs

- **Anthropic provider returns raw JSON in findings** — The consensus output from Claude shows raw JSON in finding descriptions instead of parsed structured findings. The AnthropicProvider's parseFindings doesn't extract from Claude's response format properly. Workaround: the JSON is still readable.

## Technical Debt

- **Streaming Task not cancelled on early termination** — `runReviewStreaming` creates an unstructured `Task` inside `AsyncStream` but doesn't use `continuation.onTermination` to cancel it when the consumer stops iterating.
- **Duplicate orchestration logic** — `runReview` and `runReviewStreaming` implement substantially the same workflow separately. Bug fixes to one won't reach the other.
- **No input validation on init** — DebateOrchestrator accepts negative debateRounds without validation.
- **Empty debate rounds silently continue** — If all providers fail in a debate round, it appends an empty round and keeps going.
- **No streaming output to user during model responses** — CLI shows progress between providers but waits for each provider to finish before displaying their findings. Could show tokens as they arrive.

## Pending Improvements (from Joint Chiefs reviews)

These were raised by the Joint Chiefs themselves during testing and remain unaddressed:

- Provider attribution lost in non-streaming error path
- Hardcoded logger subsystem reduces reusability
- ReviewProvider existential used across task-group boundaries without explicit Sendable guarantees
- Convergence detection heuristic is title-similarity based and may stop debate too early or too late

## Documentation Gaps

None — all initial documentation is in place.

## QA Areas Requiring Manual Verification

- [ ] Live test with all 4 providers + Claude as moderator (verified working 2026-04-09)
- [ ] Adaptive break early-stopping behavior in production
- [ ] Hub-and-spoke moderator synthesis quality
- [ ] Keychain storage with kSecAttrAccessibleWhenUnlockedThisDeviceOnly across app restarts
- [ ] CLI behavior with no API keys configured
- [ ] CLI behavior with only some providers configured
- [ ] Large file reviews (>1000 lines)
