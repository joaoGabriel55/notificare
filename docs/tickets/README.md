# Koraci — Development Tickets

Build order for the `koraci` gem (ActiveJob progress + notifications). Each ticket lists scope, acceptance criteria, and **mandatory** test coverage. No ticket is "done" without passing tests.

Source of truth: `ERD.md` at repo root.

## Build order

| # | Ticket | Depends on |
|---|---|---|
| 01 | [Gem skeleton & engine bootstrap](01-gem-skeleton.md) | — |
| 02 | [Install generator & schema](02-install-generator.md) | 01 |
| 03 | [Execution model & AS::Notifications projection](03-execution-projection.md) | 02 |
| 04 | [`ActiveJob::Progress` concern & DSL](04-progress-dsl.md) | 03 |
| 05 | [Continuable integration & resume semantics](05-continuable-integration.md) | 04 |
| 06 | [Notification model & declarative `notify_on`](06-notify-on.md) | 03 |
| 07 | [Manual `notify(...)` API & recipient enforcement](07-manual-notify.md) | 06 |
| 08 | [Hotwire broadcasts (executions + notifications)](08-hotwire-broadcasts.md) | 04, 06 |
| 09 | [View helpers](09-view-helpers.md) | 08 |
| 10 | [Mounted engine UI (Surface 1)](10-mounted-engine-ui.md) | 09 |
| 11 | [Scaffold generator (Surface 2)](11-scaffold-generator.md) | 09 |
| 12 | [Adapter matrix & CI](12-adapter-matrix-ci.md) | 05, 07 |
| 13 | [Failure & recovery test suite](13-failure-recovery-tests.md) | 05, 12 |

## Global testing rules

- **Minitest first**, Rails-native. RSpec compatibility is nice-to-have, not required.
- **95%+ coverage** on the core library (enforced via SimpleCov in CI).
- Every public API method in §5 of the ERD must have a unit test.
- Every lifecycle path in §9 of the ERD must have an integration test.
- Generator output must boot, migrate, and pass a smoke test in CI.
- Red CI blocks merge.
