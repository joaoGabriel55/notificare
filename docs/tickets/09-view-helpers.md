# 09 — View helpers

## Goal
Drop-in helpers from ERD §5: `active_job_progress(execution)` and `active_job_notifications(for: current_user)`.

## Scope
- `app/helpers/active_job/progress/view_helpers.rb` registered on `ActionView::Base`.
- `active_job_progress(execution)`:
  - Determinate (`progress_total` set): renders `<progress>` with `current/total`, percentage label, and current step.
  - Indeterminate (`progress_total` nil): renders a spinner with the current step.
  - Subscribes to the execution stream from ticket 08 via `turbo_stream_from`.
- `active_job_notifications(for:)`:
  - Renders inbox: visible (non-dismissed) notifications, unread highlighted, "mark as read", "dismiss", "clear all", and per-notification `actions` rendered as buttons/links.
  - Subscribes to the recipient's inbox stream.
- Read/dismiss/clear-all routes mounted under the engine: `PATCH /notifications/:id/read`, `PATCH /notifications/:id/dismiss`, `DELETE /notifications` (clear all for the current recipient — recipient resolved from the request's `current_user` or whatever the host app injects via the configured `current_recipient_proc` initializer setting).
- Partials seeded as stubs in ticket 02 are filled in here.

## Acceptance criteria
- Helpers render in any view in the host app without additional require.
- Both modes (determinate / indeterminate) render correctly.
- Inbox actions hit working endpoints, update state, and rebroadcast.

## Tests (mandatory)
- Helper tests rendering both helpers against fixtures and asserting key DOM (`<progress>`, `turbo-cable-stream-source`, action buttons).
- Controller tests for read/dismiss/clear-all actions: only the recipient's own notifications can be touched (authorization) — attempts against another recipient's IDs return 404.
- Integration: in the dummy app, mount the helpers in a page, run a job, assert progress moves and a notification appears in the rendered HTML on subsequent requests.
