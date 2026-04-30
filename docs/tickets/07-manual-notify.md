# 07 — Manual `notify(...)` API & recipient enforcement

## Goal
Custom milestone notifications from inside a job, plus the loud-failure contract from ERD §9 case 4.

## Scope
- Instance method `notify(title:, description: nil, metadata: {}, actions: [])` on jobs that include the concern. Writes a `Notification` row with `event_type: "custom"`, `recipient` resolved from the job's `recipient:` arg, `job_id` set.
- ERD §9 case 5: `notify(...)` after job completion is allowed — write directly, do not hinge on lifecycle hooks.
- Recipient enforcement: implemented via `ActiveJob::Notificare::Recipient` as an `around_enqueue` callback. Triggered when the job class declared `notify_on`, `uses_notify?` is true, or any `step(notify:)` was declared. Missing `recipient:` keyword → raise `ArgumentError("ImportJob requires a `recipient:` keyword argument")` *before* the adapter receives the job.
  - Detection of "uses `notify`" should be explicit: `uses_notify?` flips to true the first time `notify(...)` is called inside `perform`, and the job opts in eagerly via `uses_notify!` (escape hatch for static enqueue-time enforcement). Static parsing is brittle — prefer the explicit flag.
- `recipient:` accepts any object responding to `to_global_id`. Stored as `recipient_type`/`recipient_id`.

## Acceptance criteria
- `MyJob.perform_later(recipient: user)` then `notify(title: "halfway")` inside `perform` writes a row with `event_type: "custom"`.
- `MyJob.perform_later(file)` (no recipient) on a job that opted into notifications raises `ArgumentError` *before* the job is pushed to the adapter.
- Calling `notify(...)` after the job completes still writes a row.
- Jobs that did **not** opt into notifications are unaffected by the recipient rule.

## Tests (mandatory)
- Unit: `notify` writes the expected row with all fields.
- Unit: enqueue-time `ArgumentError` for opted-in jobs missing `recipient:`; opt-out jobs unaffected.
- Integration: `actions:` array round-trips through JSON column.
- Integration: post-completion `notify` call still persists.
