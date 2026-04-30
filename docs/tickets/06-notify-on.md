# 06 — Notification model, declarative `notify_on`, & step `notify:` row writes

## Goal
Durable, polymorphic notifications written automatically on lifecycle events the job opted into and on step boundaries declared with `step(name, notify: ...)`.

## Scope
- `app/models/active_job/notificare/notification.rb` — polymorphic `belongs_to :recipient`, `event_type` enum (`completed | failed | custom`), `read?`, `dismissed?`, `mark_read!`, `dismiss!`, default scope ordered by `created_at desc`, scopes `unread`, `visible`.
- DSL: `notify_on :completed, :failed` registers the lifecycle events that should auto-write a notification on the job class.
- Subscriber writes a notification row on the matching lifecycle transition with sensible default `title` (`"<JobClass> <event_type>"`) and `description` (nil or the exception message).
- **Step-level events:** the projection's `step_completed.active_job` handler (wired in ticket 05) graduates from a logger to writing rows. When `job.notificare_step_notify_for(step.name)` returns a non-nil value:
  - **Symbol form** (`notify: :validated`) → row with `event_type: "custom"`, `metadata.event = "validated"`, `title = "<JobClass>: validated"`.
  - **Hash form** (`notify: { event: :charged, title: "Payment captured", description: "...", metadata: {...} }`) → all keys merged into the row; `event_type` always `"custom"`.
- Recipient resolved from the job's `recipient:` keyword argument (enforcement lands in ticket 07).

## Acceptance criteria
- `notify_on :completed` produces one `active_job_notifications` row when a tracked job finishes.
- `notify_on :failed` produces one row with the exception message in `description`.
- A step declared with `notify: :event_name` produces a `Notification` row with `event_type: "custom"` and `metadata.event = "event_name"` on `step_completed.active_job`. Hash form round-trips overrides.
- A step that raises does not produce a step-level notification row; the lifecycle `failed` row may still fire if `notify_on :failed` is declared.
- `notify_on` without enqueue-time `recipient:` does **not** silently drop — error semantics live in ticket 07.

## Tests (mandatory)
- Unit: `NotificationTest` for enum, scopes, state transitions (`mark_read!`, `dismiss!`).
- Unit: `notify_on` macro registers the event list on the job class.
- Unit: step `notify: :sym` row write — assert `event_type`, `metadata.event`, default title.
- Unit: step `notify: { ... }` hash form — overrides land on the row.
- Integration: a job with `include ActiveJob::Notificare` + `notify_on :completed, :failed` produces exactly one notification on success and one on failure with correct `event_type`, `recipient`, `job_id`.
- Integration: a multi-step job with `notify:` on two of three steps produces exactly two custom notification rows after a successful run.
- Negative: a step that raises produces zero step-level notifications.
- Negative: a job without `notify_on` and without any step `notify:` produces zero notifications even on completion/failure.
