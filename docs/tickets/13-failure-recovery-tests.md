# 13 — Failure & recovery test suite

## Goal
Lock down ERD §9 + §11 "Failure & recovery" requirements with explicit tests so regressions are caught early.

## Scope
This ticket is mostly tests — the production code paths it exercises were built in tickets 03–07. Any gap discovered here is fixed in the originating ticket's code, not patched locally.

## Tests (mandatory)
- **Worker killed mid-step**: simulate via `Process.kill`-style abort in a child process running Solid Queue inline; assert no duplicate execution row on resume, `progress_current` continues from persisted value, `current_step` accurate.
- **Concurrent updates**: two threads calling `progress.advance!` interleaved with a status transition — final state consistent, no lost updates (uses `update_counters`).
- **No `tracks_progress` (case 1)**: full lifecycle, zero rows in either table.
- **Indeterminate progress (case 2)**: lifecycle works, `progress_total` stays `nil`, helpers render spinner mode.
- **Resume reuses row (case 3)**: covered by ticket 05 but re-asserted at integration level here.
- **Missing `recipient:` (case 4)**: `ArgumentError` raised before adapter receives the job — assert via spy on the adapter's `enqueue`.
- **Manual `notify` after completion (case 5)**: row written, broadcasts fire on the recipient's inbox stream.
- **Documented v1 behavior**: retried failures may write duplicate `failed` notifications. Test asserts current behavior so the day idempotency lands, this test is updated deliberately rather than silently broken.

## Acceptance criteria
- All cases listed in ERD §9 have at least one named test referencing the case number.
- Suite runs in under 60s locally (parallelize where safe).
