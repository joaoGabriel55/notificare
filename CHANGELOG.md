# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0.alpha.1] - 2026-05-03

### Added

- **Ticket 01 — Core schema & projection**: `active_job_executions` table with status state machine; `ActiveSupport::Notifications` subscriber projecting `enqueue`, `perform_start`, and `perform` events into execution rows.
- **Ticket 02 — Progress DSL**: `progress.total(n)` and `progress.advance!(by = 1)` handle on the job instance; atomic `UPDATE` via `update_all` for thread-safe increments.
- **Ticket 03 — Step DSL**: `step(name, notify: ...)` wraps `ActiveJob::Continuation`'s `step`; stashes per-step `notify:` value for the projection subscriber.
- **Ticket 04 — Notification model**: `active_job_notifications` table with polymorphic `recipient`, `event_type` enum (`completed`, `failed`, `custom`), JSON `metadata`, and `read?`/`dismissed?` predicates.
- **Ticket 05 — Recipient enforcement**: `around_enqueue` callback raises `ArgumentError` before the adapter receives a job that opted into notifications but was enqueued without `recipient:`.
- **Ticket 06 — Step-level notifications**: `step.active_job` subscriber writes a `Notification` row on successful step completion when `notify:` is declared; skipped on exception or interrupt.
- **Ticket 07 — Manual notifications**: `notify(title:, description:, metadata:, actions:)` instance method for custom mid-job notifications; `uses_notify!` / `uses_notify?` class-level opt-in helpers.
- **Ticket 08 — Hotwire broadcasts**: `Turbo::Broadcastable` integrated into both models (guarded by `defined?(Turbo::Broadcastable)`); stable stream names `active_job_progress:{job_id}` and `active_job_notifications:{gid}`.
- **Ticket 09 — View helpers**: `active_job_notificare(execution)` (progress widget) and `active_job_notifications(for: recipient)` (inbox) auto-included into `ActionView::Base`; context-aware `notificare_*_path` helpers.
- **Ticket 10 — Mounted engine UI**: `ExecutionsController` with paginated/filtered index and live-progress show page; `NotificationsController` with `read`, `dismiss`, and `clear` Turbo Stream actions; engine layout with importmap support.
- **Ticket 11 — Scaffold generator**: `rails generate active_job:notificare:scaffold JobClass` generates a controller, two views, and an I18n locale file for embedded product pages; validates the job class before generating.
- **Ticket 12 — Adapter matrix & CI**: GitHub Actions matrix covering Solid Queue + Postgres, GoodJob + Postgres, and Sidekiq + SQLite across Ruby 3.3 and 3.4.
- **Ticket 13 — Failure & recovery test suite**: Full ERD §9 test coverage — worker kill, concurrent `advance!`, resume row reuse, missing recipient, manual notify after completion, and v1 duplicate-notification documentation.

[Unreleased]: https://github.com/joaoGabriel55/notificare/compare/v0.1.0.alpha.1...HEAD
[0.1.0.alpha.1]: https://github.com/joaoGabriel55/notificare/releases/tag/v0.1.0.alpha.1
