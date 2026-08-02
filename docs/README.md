# Joint Chiefs docs — map

| Tier | What lives here | Ask yourself |
|---|---|---|
| `intent/` | PRD, value proposition, roadmap, `decisions/` (ADRs) | *why* are we building this? |
| `as-built/` | ARCHITECTURE, DATA-MODEL (current truth, no chronology) · BUG-REPORTS, KNOWN-ISSUES (dated ledgers) | what is true *now*? |
| `reference/` | Research, design system, security studies, durable evidence | durable how-to / evidence |
| `../tasks/STATUS.md` | current task state — replace, never append | what's in flight? |

Bug ledger rules: release gates read `as-built/BUG-REPORTS.md ## Open`. A bug that recurs after its fix shipped MOVES BACK to Open keeping its dated trail (`RECURRED <date> after <version> fix — fix did not hold (xN)`). Never edit inside SENTRY-RADAR markers.
