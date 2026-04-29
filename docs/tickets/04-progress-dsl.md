# 04 — `ActiveJob::Progress` concern & DSL

## Goal
The job-author surface from ERD §5: `tracks_progress`, `progress.total(n)`, `progress.advance!(by = 1)`.

## Scope
- `lib/active_job/progress/concern.rb` — `extend ActiveSupport::Concern`, class-level `tracks_progress` macro (sets `tracks_progress?` and arms the projection), instance-level `progress` returning a `ProgressHandle`.
- `lib/active_job/progress/progress_handle.rb` — `total(n)`, `advance!(by = 1)`. Writes through to the execution row using a single `UPDATE` per call (atomic increment via `update_counters` for `progress_current`).
- `progress.advance!` no-ops gracefully if the execution row hasn't been created yet (e.g., called before `perform_start`); logs at debug.
- Indeterminate state: when `total` is never called, `progress_total` stays `nil` — helpers will render a spinner.

## Acceptance criteria
- A job class including `ActiveJob::Progress` and calling `tracks_progress` opts into the projection.
- `progress.total(100)` then 100 `progress.advance!` calls leave the row at `progress_current: 100, progress_total: 100`.
- Concurrent `advance!` calls from threads yield correct final count (atomic increment).

## Tests (mandatory)
- Unit: `ConcernTest` for macro behavior and presence of `progress` accessor.
- Unit: `ProgressHandleTest` covering `total`, `advance!` (default + custom step), no-op-before-row case.
- Concurrency test: 10 threads each calling `advance!` 100 times — final `progress_current == 1000`.
- DSL test: a job whose `perform` declares `total` and advances renders correct progression in the row after the job runs inline.
