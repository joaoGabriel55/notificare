# 03 — Execution model & AS::Notifications projection

## Goal
An `ActiveJob::Notificare::Execution` (also exposed as `Notificare::Execution`) row is created/updated purely from `ActiveSupport::Notifications` events emitted by Active Job and `ActiveJob::Continuation`. No monkey-patching.

## Scope
- `app/models/active_job/notificare/execution.rb` with status enum (`enqueued | running | completed | failed`), associations to notifications via `job_id`, scopes (`recent`, `running`, `failed`).
- `lib/active_job/notificare/projection.rb` — subscriber attached to `enqueue.active_job`, `perform_start.active_job`, `perform.active_job`, and the `ActiveJob::Continuation` step events (`step_started.active_job`, `step_completed.active_job`).
- Status transitions on each event; `started_at` / `completed_at` timestamps; `error` text captured from `event.payload[:exception_object]`.
- Subscriber gated on `job.class.tracks_progress?` (returns false until ticket 04 lands; default false keeps things inert).

## Acceptance criteria
- Enqueueing a job that opts in creates exactly one execution row keyed by `job_id`.
- Performing transitions `enqueued → running → completed`; raising transitions to `failed` with `error` populated.
- Subscriber is unsubscribed cleanly in test teardown (no leaked listeners across tests).

## Tests (mandatory)
- Unit: `ExecutionTest` covering status enum, scopes, validations.
- Unit: `ProjectionTest` firing `ActiveSupport::Notifications.instrument` events directly and asserting row state — no real job runtime needed.
- Integration: a fake `TestJob` performed inline produces the expected row transitions end-to-end.
- Negative: a job without `tracks_progress` produces zero rows.
