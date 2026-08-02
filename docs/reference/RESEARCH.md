# Joint Chiefs — Research Foundation

**Version:** 1.0
**Last Updated:** 2026-04-08

## Overview

Joint Chiefs uses structured multi-agent debate to improve code review quality beyond what any single LLM can achieve. The debate mechanism is grounded in published research demonstrating that adversarial collaboration between language models produces more accurate, more truthful, and more reliable outputs.

## Primary Citation

**Liang, T., He, Z., Jiao, W., Wang, X., Wang, Y., Wang, R., Yang, Y., Tu, Z., & Shi, S. (2023).** "Encouraging Divergent Thinking in Large Language Models through Multi-Agent Debate."

- **Paper:** [arXiv:2305.19118](https://arxiv.org/abs/2305.19118)
- **Code:** [github.com/Skytliang/Multi-Agents-Debate](https://github.com/Skytliang/Multi-Agents-Debate)

## Key Findings from the MAD Paper

### The Degeneration of Thought (DoT) Problem

When a single LLM is asked to reflect on and revise its own output, its confidence increases over successive rounds — regardless of whether the answer is actually correct. The paper calls this "Degeneration of Thought." Self-reflection creates a feedback loop where the model reinforces its initial position rather than genuinely reconsidering it. This makes single-model "self-debate" unreliable for improving correctness.

### Multi-Agent Debate Improves Truthfulness

When multiple independent models debate — each seeing the others' arguments and forced to respond substantively — accuracy improves significantly. The adversarial dynamic prevents any single model from going unchallenged. Models with different architectures and training data expose each other's blind spots.

### Adaptive Stopping Matters

Forcing debate to continue after positions have converged degrades output quality. The paper shows that debate should stop when consensus is reached, not after a fixed number of rounds. Continued rounds after agreement introduce noise and can cause models to second-guess correct conclusions.

## How Joint Chiefs Implements Each Principle

### 1. DoT Prevention via Independent Models

Joint Chiefs dispatches code to 2-5 different LLM providers (OpenAI, Gemini, Grok, Ollama) simultaneously. Each model performs an independent initial review without seeing others' findings. Because these models have different architectures, training data, and biases, they naturally produce divergent analyses. This structural independence is the primary defense against DoT — no model is reflecting on its own output.

### 2. Tit-for-Tat Engagement

During debate rounds, each model receives the full set of prior findings and must address each one by title, taking a clear position: agree, challenge, or revise. The prompt structure prevents models from ignoring inconvenient findings or simply restating their own position. Every finding gets substantive engagement from every model.

### 3. Adaptive Break (Early Consensus Detection)

The `DebateOrchestrator` monitors agreement levels across rounds. When all active findings reach unanimous or near-unanimous agreement, debate terminates early rather than running the full configured number of rounds. This prevents the quality degradation that comes from over-debating settled questions.

### 4. Judge Arbitration for Deadlocks

When debate rounds complete without full consensus, a designated judge model (Claude by default) reads the complete debate transcript and synthesizes the final summary. The judge evaluates the quality of reasoning behind each position, not just the vote count. A single model with strong evidence and clear logic can prevail over a poorly-justified majority.

## Why This Matters for Code Review

Code review is a domain where multi-agent debate is particularly effective:

- **Models have different blind spots.** One model might catch security issues but miss performance problems. Another might flag race conditions but overlook API misuse. Independent parallel review ensures broader coverage than any single model.
- **Debate surfaces false positives.** When one model flags an issue and others challenge it with specific reasoning, false positives get filtered out. This improves the signal-to-noise ratio of the final review.
- **Consensus findings are higher confidence.** A bug that three independent models agree on is far more likely to be a real problem than one flagged by a single model. The agreement level metadata lets developers triage findings effectively.
- **Disagreements are informative.** When models disagree about a finding, the debate transcript shows exactly why. This gives developers the context to make their own judgment call, rather than receiving an opaque thumbs-up or thumbs-down.

## Revision History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-04-08 | Initial research documentation |
