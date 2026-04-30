# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem is

`koraci` (Bosnian for "steps") is a Rails engine gem that adds persisted progress tracking and a notification inbox to ActiveJob jobs. It is a **projection layer over `ActiveJob::Continuable`** — Continuable owns execution and continuation state; this gem owns the persisted projection of that state, a notification inbox primitive, and the Hotwire UI for both.

Two concepts, intentionally separate:
- **Progress** (`active_job_executions`) — transient live state of a running job (status, current step, progress_current/total)
- **Notifications** (`active_job_notifications`) — durable user-facing records of job events (completed, failed, custom milestones)

The product roadmap lives in `docs/tickets/README.md`. The full schema and API contract are in `ERD.md`.

## Commands

```bash
# Run the full test suite (also the default rake task)
bundle exec rake test

# Run a single test file
bundle exec ruby -Itest test/active_job/progress/projection_test.rb

# Run a single test by name
bundle exec ruby -Itest test/active_job/progress/projection_test.rb -n "test_enqueue_event_creates_an_execution_row_with_enqueued_status"

# Lint
bundle exec rubocop
bundle exec rubocop -a   # auto-correct
```

Tests run against a SQLite dummy Rails app in `test/dummy/`. Migrations are applied automatically at test boot via `test/test_helper.rb`. SimpleCov enforces **95% minimum coverage** — running a single file will fail the coverage gate; run the full suite to verify.

## Architecture

### Gem structure

```
lib/
  active_job/progress.rb              # entry point; requires engine, progress_handle, concern
  active_job/progress/engine.rb       # Rails::Engine (isolated_namespace); calls Projection.subscribe! on init
  active_job/progress/projection.rb   # AS::Notifications subscriber
  active_job/progress/concern.rb      # ActiveSupport::Concern; tracks_progress macro + progress accessor
  active_job/progress/progress_handle.rb  # ProgressHandle — total(n) / advance!(by=1)
  active_job/progress/version.rb
  koraci.rb                           # requires active_job/progress; defines Koraci module (alias target)
  generators/…                        # install generator
app/
  models/active_job/progress/
    application_record.rb         # engine's abstract base record
    execution.rb                  # ActiveRecord model for active_job_executions
  views/active_job/progress/      # shared view partials (stub; populated by install generator)
```

### How the projection works

`Projection` (`lib/active_job/progress/projection.rb`) subscribes to three ActiveSupport::Notifications events:

| Event | Action |
|---|---|
| `enqueue.active_job` | `find_or_create_by!(job_id:)` with `status: enqueued` |
| `perform_start.active_job` | update to `status: running`, set `started_at` |
| `perform.active_job` | update to `completed` or `failed`; capture `exception_object.message` into `error` |

All handlers are gated on `job.class.tracks_progress?` — jobs without this method (or returning false) produce no rows. The gate is the primary opt-in mechanism; job authors opt in via `include ActiveJob::Progress` + `tracks_progress` (see `concern.rb`).

Exception info is available in `event.payload[:exception_object]` because `ActiveSupport::Notifications#instrument` itself rescues and re-raises, adding exception data to the payload before notifying subscribers.

`Projection.subscribe!` / `unsubscribe!` manage a module-level `SUBSCRIPTIONS` array. The engine calls `subscribe!` in its initializer. Tests call `unsubscribe!` + `subscribe!` in setup and `unsubscribe!` in teardown to ensure isolation.

### Execution model

`ActiveJob::Progress::Execution` (`app/models/active_job/progress/execution.rb`):
- `status` enum maps strings to strings: `{ enqueued: "enqueued", running: "running", completed: "completed", failed: "failed" }`
- `enum` macro generates `.running` and `.failed` scopes; `.recent` is defined explicitly
- `Koraci::Execution` is an alias, set via `config.to_prepare` in the engine

### Test dummy app

`test/dummy/` is a full Rails app used only for tests. Its migration (`test/dummy/db/migrate/`) defines both tables. Test jobs live in `test/dummy/app/jobs/`:
- `TrackedTestJob` — opts in via `def self.tracks_progress? = true`
- `FailingTrackedTestJob` — opts in and raises `StandardError`
- `UntrackedTestJob` — no `tracks_progress?`; expects zero execution rows
- `ProgressDslTestJob` — uses `include ActiveJob::Progress` + `tracks_progress`; calls `progress.total` and `progress.advance!` in `perform`

`ProjectionTest` uses `include ActiveJob::TestHelper` and `perform_enqueued_jobs` (not `with_queue_adapter`, which doesn't exist in this Rails version) to drive integration paths.

## Key conventions

- **No monkey-patching.** All hooks go through `ActiveSupport::Notifications`. If an upstream Continuable event is missing, open a PR there.
- **`tracks_progress?` is the opt-in gate.** Default is falsy (method absent). Define it by including `ActiveJob::Progress` and calling `tracks_progress` in the job class body.
- **Rubocop uses `rubocop-rails-omakase`**, configured in `.rubocop.yml`. `test/dummy/` is excluded from linting.
- The `test/dummy/` Gemfile is separate from the gem's Gemfile; do not add test dependencies there.
