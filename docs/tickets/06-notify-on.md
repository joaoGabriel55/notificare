# 06 — Notification model & declarative `notify_on`

## Goal
Durable, polymorphic notifications written automatically on lifecycle events the job opted into.

## Scope
- `app/models/active_job/progress/notification.rb` — polymorphic `belongs_to :recipient`, `event_type` enum (`completed | failed | custom`), `read?`, `dismissed?`, `mark_read!`, `dismiss!`, default scope ordered by `created_at desc`, scopes `unread`, `visible`.
- DSL: `notify_on :completed, :failed` registers the lifecycle events that should auto-write a notification on the job class.
- Subscriber writes a notification row on the matching lifecycle transition with sensible default `title` (`"<JobClass> <event_type>"`) and `description` (nil or the error message).
- Recipient resolved from the job's `recipient:` keyword argument (enforcement lands in ticket 07).

## Acceptance criteria
- `notify_on :completed` produces one `active_job_notifications` row when a tracked job finishes.
- `notify_on :failed` produces one row with the exception message in `description`.
- `notify_on` without enqueue-time `recipient:` does **not** silently drop — error semantics live in ticket 07.

## Tests (mandatory)
- Unit: `NotificationTest` for enum, scopes, state transitions (`mark_read!`, `dismiss!`).
- Unit: `notify_on` macro registers the event list on the job class.
- Integration: a job with `tracks_progress` + `notify_on :completed, :failed` produces exactly one notification on success and one on failure with correct `event_type`, `recipient`, `job_id`.
- Negative: a job without `notify_on` produces zero notifications even on completion/failure.
