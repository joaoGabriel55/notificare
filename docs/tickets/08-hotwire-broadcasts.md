# 08 — Hotwire broadcasts (executions + notifications)

## Goal
ERD §7: row changes broadcast automatically. No manual `broadcast_*` calls in user code.

## Scope
- `Execution` `broadcasts_refreshes_to` itself (Turbo Streams `morph` strategy where available; fall back to `replace` on older Turbo).
- `Notification` `broadcasts_refreshes_to` keyed on `[recipient_type, recipient_id]` so a recipient's inbox updates regardless of which job wrote.
- Stream names documented and stable (part of the public surface, since helpers in ticket 09 subscribe to them):
  - Execution: `["active_job_notificare", execution.job_id]`
  - Notifications inbox: `["active_job_notifications", recipient.to_gid_param]`
- Action Cable / Solid Cable / async adapter all supported (test against Action Cable test adapter).

## Acceptance criteria
- Updating `progress_current` on an execution row produces a Turbo Stream broadcast.
- Inserting a notification for a recipient produces a broadcast on that recipient's inbox stream.
- No broadcasts fire when `tracks_progress` was not declared (no row → no callback).

## Tests (mandatory)
- Unit: `Turbo::Streams::ActionBroadcastJob` enqueued on update (use `assert_broadcasts` / Turbo's test helpers).
- Unit: stream names match the documented format exactly — pin them with a test so refactors don't silently change them.
- Integration: end-to-end broadcast captured via the Action Cable test adapter from a real job run.
