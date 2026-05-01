# 09 — View helpers

## Goal
Drop-in helpers from ERD §5: `active_job_notificare(execution)` and `active_job_notifications(for: current_user)`.

## Scope
- `app/helpers/active_job/notificare/view_helpers.rb` registered on `ActionView::Base`.
- `active_job_notificare(execution)`:
  - Determinate (`progress_total` set): renders `<progress>` with `current/total`, percentage label, and current step.
  - Indeterminate (`progress_total` nil): renders a spinner with the current step.
  - Subscribes to the execution stream from ticket 08 via `turbo_stream_from`.
- `active_job_notifications(for:)`:
  - Renders inbox: visible (non-dismissed) notifications, unread highlighted, "mark as read", "dismiss", "clear all", and per-notification `actions` rendered as buttons/links.
  - Subscribes to the recipient's inbox stream.
- Read/dismiss/clear-all routes mounted under the engine: `PATCH /notifications/:id/read`, `PATCH /notifications/:id/dismiss`, `DELETE /notifications` (clear all for the current recipient — recipient resolved from the request's `current_user` or whatever the host app injects via the configured `current_recipient_proc` initializer setting).
- Partials seeded as stubs in ticket 02 are filled in here.
- **Default CSS classes** on all structural elements so host apps can style without inspecting markup:
  - `_progress.html.erb`: wrapper `notificare-progress`, bar `notificare-progress__bar`, label `notificare-progress__label`, step `notificare-progress__step`, spinner `notificare-progress__spinner`.
  - `_notifications.html.erb`: inbox wrapper `notificare-inbox`, each item `notificare-notification`, unread modifier `notificare-notification--unread`, title `notificare-notification__title`, description `notificare-notification__description`, actions container `notificare-notification__actions`.
- **I18n for all button/link labels** in `_notifications.html.erb` — no static English strings in the partial; all user-visible text goes through `t()` with default translations in `config/locales/en.yml`. Host apps override any key in their own locale files:
  - `active_job.notificare.notifications.clear_all` → `"Clear all"`
  - `active_job.notificare.notifications.mark_as_read` → `"Mark as read"`
  - `active_job.notificare.notifications.dismiss` → `"Dismiss"`

## Acceptance criteria
- Helpers render in any view in the host app without additional require.
- Both modes (determinate / indeterminate) render correctly.
- Inbox actions hit working endpoints, update state, and rebroadcast.
- All structural elements carry their documented `notificare-*` CSS class.
- All user-visible strings in the inbox partial are driven by I18n keys; changing the locale file changes the rendered text.

## Tests (mandatory)
- Helper tests rendering both helpers against fixtures and asserting key DOM (`<progress>`, `turbo-cable-stream-source`, action buttons, CSS classes).
- Controller tests for read/dismiss/clear-all actions: only the recipient's own notifications can be touched (authorization) — attempts against another recipient's IDs return 404.
- Integration: in the dummy app, mount the helpers in a page, run a job, assert progress moves and a notification appears in the rendered HTML on subsequent requests.
