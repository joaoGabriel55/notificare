# 07 — Manual `notify(...)` API & recipient enforcement

## Goal
Custom milestone notifications from inside a job, plus the loud-failure contract from ERD §9 case 4.

## Scope
- Instance method `notify(title:, description: nil, metadata: {}, actions: [])` on jobs that include the concern. Writes a `Notification` row with `event_type: "custom"`, `recipient` resolved from the job's `recipient:` arg, `job_id` set.
- ERD §9 case 5: `notify(...)` after job completion is allowed — write directly, do not hinge on lifecycle hooks.
- Recipient enforcement: at enqueue time, if the job class declared `notify_on` *or* the source contains a call to `notify(`, require a `recipient:` keyword. Missing → raise `ArgumentError("ImportJob requires a `recipient:` keyword argument")`. Implement via an `enqueue` callback that introspects the job's arguments.
  - Detection of "uses `notify`" should be explicit: a class-level flag set when the concern detects a `notify` call site or the job opts in via `notifies_manually!` (escape hatch). Static parsing is brittle — prefer the explicit flag.
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
