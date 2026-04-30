# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this gem is

`notificare` (Romanian: *"to notify"*) is a Rails engine gem that adds persisted progress tracking and a notification inbox to ActiveJob jobs. It is a **projection layer over `ActiveJob::Continuation`** (shipped in Rails 8.1) — Continuation owns execution and step-resume state; this gem owns the persisted projection of that state, a notification inbox primitive, and the Hotwire UI for both. Step boundaries become a state machine that drives notifications.

> The gem was renamed from `koraci` (Bosnian: "steps") to `notificare` on 2026-04-30 to reflect its center of gravity (the inbox, seeded by step-level state-machine events) and to use a name that travels well across languages.

Two concepts, intentionally separate:
- **Progress** (`active_job_executions`) — transient live state of a running job (status, current step, progress_current/total)
- **Notifications** (`active_job_notifications`) — durable user-facing records of job events (completed, failed, per-step custom milestones)

The product roadmap lives in `docs/tickets/README.md`. The full schema and API contract are in `ERD.md`.

## Commands

```bash
# Run the full test suite (also the default rake task)
bundle exec rake test

# Run a single test file
bundle exec ruby -Itest test/active_job/notificare/projection_test.rb

# Run a single test by name
bundle exec ruby -Itest test/active_job/notificare/projection_test.rb -n "test_enqueue_event_creates_an_execution_row_with_enqueued_status"

# Lint
bundle exec rubocop
bundle exec rubocop -a   # auto-correct
```

Tests run against a SQLite dummy Rails app in `test/dummy/`. Migrations are applied automatically at test boot via `test/test_helper.rb`. SimpleCov enforces **95% minimum coverage** — running a single file will fail the coverage gate; run the full suite to verify.

## Architecture

### Gem structure

```
lib/
  notificare.rb                          # top-level shim; defines Notificare module
  active_job/notificare.rb               # entry point; requires engine, progress_handle, step_dsl, concern
  active_job/notificare/engine.rb        # Rails::Engine (isolated_namespace); calls Projection.subscribe! on init
  active_job/notificare/projection.rb    # AS::Notifications subscriber
  active_job/notificare/concern.rb       # ActiveSupport::Concern; auto-includes ActiveJob::Continuable + StepDSL
  active_job/notificare/step_dsl.rb      # wraps Continuation's `step` with notify: kwarg; stashes per-step events
  active_job/notificare/progress_handle.rb  # ProgressHandle — total(n) / advance!(by=1)
  active_job/notificare/recipient.rb        # Recipient — around_enqueue enforcement of recipient: kwarg
  active_job/notificare/version.rb
  generators/…                           # install generator (active_job:notificare:install)
app/
  models/active_job/notificare/
    application_record.rb         # engine's abstract base record
    execution.rb                  # ActiveRecord model for active_job_executions
    notification.rb               # ActiveRecord model for active_job_notifications
  views/active_job/notificare/    # shared view partials (stub; populated by install generator)
```

### How the projection works

`Projection` (`lib/active_job/notificare/projection.rb`) subscribes to five ActiveSupport::Notifications events:

| Event | Action |
|---|---|
| `enqueue.active_job` | `find_or_create_by!(job_id:)` with `status: enqueued`; rescues `RecordNotUnique` for race safety |
| `perform_start.active_job` | if already `running` (resume path): clear stale error, preserve `progress_current`/`started_at`; otherwise set `status: running, started_at` |
| `step_started.active_job` | mirror `step.name` onto `current_step`; fired by `ActiveJob::Continuation` at each step boundary |
| `step.active_job` | fired by `ActiveJob::Continuation` after each step finishes (success or failure). If step completed without exception and not interrupted, reads the `notify:` value stashed by `StepDSL` and writes a `Notification` row |
| `perform.active_job` | update to `completed` or `failed`; capture `exception_object.message` into `error`; write lifecycle `Notification` row if `notify_on` declared the matching event |

All handlers are gated on `job.class.tracks_progress?` — under the new umbrella, including `ActiveJob::Notificare` flips this to true by default; `tracks_progress false` opts out. Jobs without the include (or with `tracks_progress?` returning false) produce no rows.

Exception info is available in `event.payload[:exception_object]` because `ActiveSupport::Notifications#instrument` itself rescues and re-raises, adding exception data to the payload before notifying subscribers.

**Resume semantics (ERD §9 case 3):** when a worker is killed mid-step, `perform.active_job` never fires and the row stays `running`. On re-enqueue, `find_or_create_by!` finds the existing row (no duplicate). On the next `perform_start`, the `running?` check detects the resume path and skips resetting `progress_current` and `started_at`. There is no `continuation_state` column — `ActiveJob::Continuation` owns that (ERD §6).

`Projection.subscribe!` / `unsubscribe!` manage a module-level `SUBSCRIPTIONS` array. The engine calls `subscribe!` in its initializer. Tests call `unsubscribe!` + `subscribe!` in setup and `unsubscribe!` in teardown to ensure isolation.

### Concern + Step DSL

`include ActiveJob::Notificare` is the single seam. The concern auto-includes `ActiveJob::Continuable` (Continuation's includable concern), `StepDSL`, and `Recipient`. `StepDSL#step(name, notify: ..., **opts, &block)` pops `notify:` out of the kwargs, stashes it on the job instance keyed by step name (`@_notificare_step_notify`), and forwards everything else to Continuation's `step`. The `step_completed.active_job` handler reads the stash off `event.payload[:job]` via `notificare_step_notify_for(step_name)`. Calling `step(notify:)` also sets a class-level `@_has_step_notifications` flag (read by `has_step_notifications?`) which is used by `Recipient` for enqueue-time enforcement.

The `notify:` stash is read in the `step.active_job` subscriber (ticket 06). Rows are written only when the step completed without exception and was not interrupted.

**`notify(title:, description: nil, metadata: {}, actions: [])` instance method**: writes a `Notification` row with `event_type: "custom"` directly — does not rely on lifecycle hooks, so it is safe to call at any point during or after `perform` (ERD §9 case 5). Silently skips if `self.recipient` is nil. Also flips `self.class.uses_notify!` on first call so subsequent enqueues of that job class are subject to recipient enforcement.

**`uses_notify!` / `uses_notify?` class methods**: `uses_notify!` eagerly opts a job class into enqueue-time recipient enforcement (call it at class definition if you know the job will call `notify` but want the `ArgumentError` to fire on the very first enqueue, before any instance has run). `uses_notify?` returns true after `uses_notify!` is called or after any instance has called `notify(...)`.

### Notification model

`ActiveJob::Notificare::Notification` (`app/models/active_job/notificare/notification.rb`):
- Polymorphic `belongs_to :recipient` (resolved from `job.recipient` at write time)
- `event_type` enum: `{ completed: "completed", failed: "failed", custom: "custom" }` — `custom` is used for step-level events
- `metadata` stored as JSON text (SQLite); contains at minimum `{ "event" => "<event_name>" }` for custom rows
- `read?` / `dismissed?` predicates; `mark_read!` / `dismiss!` state transitions
- Default scope: `order(created_at: :desc)`; named scopes: `unread`, `visible` (not dismissed)
- `Notificare::Notification` alias registered in `config.to_prepare`

**`notify_on` DSL** (on the job class): `notify_on :completed, :failed` registers which lifecycle events auto-write a row. Registered list is stored as `@_notificare_notify_on` and read via `notificare_notify_on`. The row's title defaults to `"<JobClass> <event_type>"` and description carries the exception message for `failed` rows.

**Step-level notifications**: `step(:name, notify: :sym)` or `step(:name, notify: { event:, title:, description:, metadata: })` in the job's `perform`. The `step.active_job` subscriber writes a `Notification` row with `event_type: "custom"` when the step completes without error. Hash form allows full override of title, description, and extra metadata keys.

**Recipient**: set via `self.recipient = <record>` inside `perform`. If nil at write time, the write is silently skipped. Enqueue-time enforcement is provided by `ActiveJob::Notificare::Recipient` (`lib/active_job/notificare/recipient.rb`): an `around_enqueue` callback that raises `ArgumentError` before the adapter receives the job when `recipient:` is missing and the job has opted into notifications (via `notify_on`, `uses_notify!`, or `has_step_notifications?`). `recipient:` must be passed as a keyword argument to `perform_later`; it is detected by inspecting `self.arguments` for a hash with a `:recipient` or `"recipient"` key.

### Execution model

`ActiveJob::Notificare::Execution` (`app/models/active_job/notificare/execution.rb`):
- `status` enum maps strings to strings: `{ enqueued: "enqueued", running: "running", completed: "completed", failed: "failed" }`
- `enum` macro generates `.running` and `.failed` scopes; `.recent` is defined explicitly
- `Notificare::Execution` is an alias, set via `config.to_prepare` in the engine

### Test dummy app

`test/dummy/` is a full Rails app used only for tests. Its migration (`test/dummy/db/migrate/`) defines both tables. Test jobs live in `test/dummy/app/jobs/`:
- `TrackedTestJob` — opts in via `def self.tracks_progress? = true` (legacy shape; still works with the projection's gate)
- `FailingTrackedTestJob` — opts in and raises `StandardError`
- `UntrackedTestJob` — no `tracks_progress?`; expects zero execution rows
- `ProgressDslTestJob` — uses `include ActiveJob::Notificare`; calls `progress.total` and `progress.advance!` in `perform`
- `StepDslTestJob` — uses `include ActiveJob::Notificare`; declares `step(:validate, notify: :validated)` and `step(:finalize)` for StepDSL coverage
- `NotifyOnTestJob` — uses `notify_on :completed, :failed`; sets `self.recipient` from a `recipient:` kwarg
- `FailingNotifyOnTestJob` — same as above but raises `StandardError` in `perform`
- `StepNotifyTestJob` — three steps: `:validate` (notify: :validated), `:process` (notify: hash form), `:finalize` (no notify)
- `FailingStepNotifyTestJob` — `:ok_step` (notify: :ok_done) succeeds; `:boom_step` raises
- `ManualNotifyTestJob` — uses `notify_on :completed`; calls `notify(title:, description:, metadata:, actions:)` inside `perform` for ticket-07 coverage
- `UsesNotifyTestJob` — calls `uses_notify!` at class definition; used to verify enqueue-time enforcement before any instance has run

`ProjectionTest` uses `include ActiveJob::TestHelper` and `perform_enqueued_jobs` (not `with_queue_adapter`, which doesn't exist in this Rails version) to drive integration paths.

Continuation step events are simulated in unit tests using `fake_step(name)` (a `Struct.new(:name)` double) passed to `instrument("step_started.active_job", ...)` / `instrument("step.active_job", job:, step:, interrupted: false)`. Note: `ActiveJob::Continuation` fires `step.active_job` (not `step_completed.active_job`) after each step block finishes; the payload includes `interrupted:` and `exception_object` (set by AS::Notifications when the block raises).

**Important**: `ActiveJob::Continuable#continue` rescues `StandardError` and calls `retry_job(wait: 5.seconds)` when `continuation.advanced?` is true (at least one step completed). This means a step-raising job does NOT re-raise in tests — `perform_enqueued_jobs` returns without error and the retry is scheduled in the future. Use plain `perform_enqueued_jobs` (no `assert_raises`) for jobs that fail mid-step after making progress.

## Key conventions

- **No monkey-patching.** All hooks go through `ActiveSupport::Notifications`. If an upstream `ActiveJob::Continuation` event is missing, open a PR there.
- **`include ActiveJob::Notificare` is the opt-in.** It auto-includes `ActiveJob::Continuable`. `tracks_progress?` defaults to true after the include; `tracks_progress false` opts out without removing the include.
- **Rubocop uses `rubocop-rails-omakase`**, configured in `.rubocop.yml`. `test/dummy/` is excluded from linting.
- The `test/dummy/` Gemfile is separate from the gem's Gemfile; do not add test dependencies there.
