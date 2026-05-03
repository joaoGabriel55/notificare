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

# Run adapter integration tests (requires adapter gems; see test/adapters/)
bundle exec ruby -Itest test/adapters/solid_queue_test.rb   # SQLite, SolidQueue
bundle exec ruby -Itest test/adapters/sidekiq_test.rb       # SQLite, Sidekiq fake mode
QUEUE_ADAPTER=good_job DATABASE_URL=postgresql://... bundle exec ruby -Itest test/adapters/good_job_test.rb

# Lint
bundle exec rubocop
bundle exec rubocop -a   # auto-correct
```

Tests run against a SQLite dummy Rails app in `test/dummy/`. Migrations are applied automatically at test boot via `test/test_helper.rb`. SimpleCov enforces **95% minimum coverage** — running a single file will fail the coverage gate; run the full suite to verify.

### Adapter integration tests (`test/adapters/`)

Three test files exercise the projection against real queue adapters. They **do not** use SimpleCov (they run individually, not as part of `rake test`) and have their own test helper (`test/adapters/adapter_test_helper.rb`) that:
1. Skips SimpleCov
2. Loads the dummy app environment
3. Runs Notificare migrations via `AdapterTestHelper.prepare_database!`
4. Loads adapter-specific schema (e.g. SolidQueue tables from `test/dummy/db/queue_schema.rb`)

**Drain patterns** (the key design decision for each adapter):

| Adapter | Drain method | Why |
|---|---|---|
| `solid_queue` | Iterate `SolidQueue::ReadyExecution.includes(:job)`, call `ActiveJob::Base.execute(job.arguments)`, mark finished | SolidQueue has no built-in synchronous test drain; we use its internal execution path |
| `good_job` | Set `GoodJob.configuration.options[:execution_mode] = :external` in setup (prevents `:inline` default from executing jobs during `perform_later`), then call `GoodJob.perform_inline` to drain | GoodJob defaults to `:inline` in the test environment — without `:external`, `perform_later` executes inline before `enqueue.active_job` fires, leaving the execution row stuck at `enqueued` |
| `sidekiq` | `Sidekiq.testing!(:fake)` at file load + `Sidekiq::Job.drain_all` per test | Sidekiq fake mode buffers jobs; `drain_all` executes them synchronously via `Sidekiq::ActiveJob::Wrapper#perform` |

**Event-ordering invariant**: all three drains ensure `enqueue.active_job` fires (and creates the Execution row) **before** `perform_start.active_job` / `perform.active_job`. This is the same constraint documented under "Hotwire broadcast internals" above — inline execution during the enqueue instrumentation block would lose the row.

**Database**: adapter tests support `DATABASE_URL` to switch from SQLite to Postgres. Rails merges the URL with `database.yml`'s test section automatically. GoodJob tests require Postgres (uses `jsonb`). SolidQueue and Sidekiq tests work with SQLite.

**CI**: `.github/workflows/ci.yml` runs adapter tests in a separate matrix job (`adapter-tests`) with services for Postgres (port 5432) and Redis (port 6379). Valid matrix combinations:
- `solid_queue` + `postgres` × `ruby: [3.3, 3.4]`
- `good_job` + `postgres` × `ruby: [3.3, 3.4]`
- `sidekiq` + `sqlite` × `ruby: [3.3, 3.4]`

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
  generators/active_job/notificare/
    install/                             # active_job:notificare:install — migration, initializer, view partials
    scaffold/                            # active_job:notificare:scaffold <JobClass> — controller + views for embedded product pages
app/
  assets/stylesheets/active_job/notificare/
    engine.css                    # minimal BEM stylesheet for the admin UI (nf-* class prefix)
  controllers/active_job/notificare/
    application_controller.rb     # engine's base controller (ActionController::Base)
    executions_controller.rb      # GET :index (paginated + filtered list), GET :show (detail + live progress)
    notifications_controller.rb   # PATCH :read, PATCH :dismiss, DELETE :clear (collection)
  helpers/active_job/notificare/
    view_helpers.rb               # active_job_notificare(execution), active_job_notifications(for:)
  models/active_job/notificare/
    application_record.rb         # engine's abstract base record
    execution.rb                  # ActiveRecord model for active_job_executions
    notification.rb               # ActiveRecord model for active_job_notifications
  views/layouts/active_job/notificare/
    application.html.erb          # engine layout: includes engine.css + importmap JS if available
  views/active_job/notificare/
    executions/
      index.html.erb              # paginated list with status/job_class filters and pagination
      show.html.erb               # execution detail: metadata, live progress widget, tied notifications
    _progress.html.erb            # determinate <progress> or indeterminate spinner + turbo_stream_from
    _notifications.html.erb       # inbox wrapper: turbo_stream_from + clear-all + renders _notification per item
    _notification.html.erb        # single notification card wrapped in turbo_frame_tag dom_id(notification)
    notifications/
      read.turbo_stream.erb       # turbo_stream.replace — swaps card with updated state (unread class removed)
      dismiss.turbo_stream.erb    # turbo_stream.remove — removes the notification's turbo-frame from DOM
      clear.turbo_stream.erb      # turbo_stream.remove for each notification in @notifications
config/
  routes.rb                       # root→executions#index; resources :executions; PATCH /notifications/:id/read|dismiss, DELETE /notifications
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
- When `turbo-rails` is available (`defined?(Turbo::Broadcastable)`), includes `Turbo::Broadcastable` and calls `broadcasts_refreshes_to ->(execution) { [ "active_job_progress", execution.job_id ] }`. This fires an `after_commit` that enqueues `Turbo::Streams::BroadcastStreamJob` on every create/update. The stable stream name is `"active_job_progress:{job_id}"` (unsigned, as passed to `ActionCable.server.broadcast`).

### Notification model (broadcast addition)

`ActiveJob::Notificare::Notification` (`app/models/active_job/notificare/notification.rb`) also includes `Turbo::Broadcastable` (when available) and registers an `after_commit :broadcast_notification_refresh` callback. That private method guards on `recipient` presence and calls `broadcast_refresh_later_to "active_job_notifications", recipient.to_gid_param`. The stable stream name is `"active_job_notifications:{recipient.to_gid_param}"`.

### View helpers

`ActiveJob::Notificare::ViewHelpers` (`app/helpers/active_job/notificare/view_helpers.rb`) is auto-included into `ActionView::Base` via an engine initializer. Two public helpers:

- **`active_job_notificare(execution)`**: renders `_progress.html.erb`. If `execution.progress_total` is set, renders a `<progress class="notificare-progress__bar">` element with `current/total` counts (`.notificare-progress__label`) and a percentage label. Otherwise renders an indeterminate spinner (`.notificare-progress__spinner`). Both modes show `current_step` as `.notificare-progress__step` if present. Root wrapper is `div.notificare-progress`. Subscribes to the execution's ActionCable stream via `turbo_stream_from "active_job_progress", execution.job_id`.
- **`active_job_notifications(for: recipient)`**: fetches `Notification.where(recipient:).visible` and renders `_notifications.html.erb`. Root wrapper is `div#active_job_notifications.notificare-inbox`. The inbox partial iterates notifications and delegates each card to `render "active_job/notificare/notification", notification: notification` (`_notification.html.erb`). Each card is wrapped in `turbo_frame_tag dom_id(notification)` so controller actions can replace or remove individual cards without a page redirect. Title is `strong.notificare-notification__title`, description is `p.notificare-notification__description`, action buttons/links live in `div.notificare-notification__actions`. Subscribes via `turbo_stream_from "active_job_notifications", recipient.to_gid_param`.

**Internal route helpers** — three context-aware path helpers are also mixed in:
- **`notificare_read_notification_path(notification)`**: resolves to `read_notification_path(notification)` in engine context; falls back to `url_for(controller: "active_job/notificare/notifications", action: "read", ...)` in host-app views.
- **`notificare_dismiss_notification_path(notification)`**: same pattern for the dismiss action.
- **`notificare_clear_notifications_path`**: same pattern for the clear (collection delete) action.

These helpers are available for scaffold-generated or custom host-app views that need to reference engine routes without the `notificare.` engine proxy. The installed partials (`_notifications.html.erb`, `_notification.html.erb`) still use `notificare.X` directly and require the `as: :notificare` mount alias.

**CSS class reference (`notificare-*` prefix, all stable and intended for host-app overrides)**:

| Element | Class |
|---|---|
| Progress wrapper | `notificare-progress` |
| Determinate bar | `notificare-progress__bar` |
| Fraction/percentage label | `notificare-progress__label` |
| Current step name | `notificare-progress__step` |
| Indeterminate spinner | `notificare-progress__spinner` |
| Notifications inbox wrapper | `notificare-inbox` |
| Notification item | `notificare-notification` |
| Unread modifier | `notificare-notification--unread` |
| Notification title | `notificare-notification__title` |
| Notification description | `notificare-notification__description` |
| Notification actions container | `notificare-notification__actions` |

**I18n keys** — all button/link labels in `_notifications.html.erb` use dot-shorthand `t()` calls resolved from `config/locales/en.yml`. Host apps override any key in their own locale files:

| Key | Default (en) |
|---|---|
| `active_job.notificare.notifications.clear_all` | `"Clear all"` |
| `active_job.notificare.notifications.mark_as_read` | `"Mark as read"` |
| `active_job.notificare.notifications.dismiss` | `"Dismiss"` |

### Executions controller (admin UI)

`ActiveJob::Notificare::ExecutionsController` (`app/controllers/active_job/notificare/executions_controller.rb`) provides the admin status page at the engine root:

- `GET /` → `#index` — paginated list of executions (25 per page). Accepts `?status=` and `?job_class=` query params for filtering. Sets `@executions`, `@page`, `@total_count`, `@total_pages`, `@statuses`, `@job_classes`. Passes `@statuses` because ERB templates in engine views cannot resolve `Execution` as a bare constant (no engine namespace in view binding).
- `GET /:id` → `#show` — single execution detail: metadata, the existing `_progress.html.erb` partial (live progress via Turbo Stream), and recent notifications tied to `@execution.job_id`.

**Authentication**: gated by `before_action :authenticate_notificare!`. Behavior:
- `ActiveJob::Notificare.authenticate_with = nil` + production env → `403 Forbidden` (fail-safe default)
- `ActiveJob::Notificare.authenticate_with = nil` + non-production → allow (dev/test convenience)
- `ActiveJob::Notificare.authenticate_with = -> { false }` → `403 Forbidden` (regardless of env)
- `ActiveJob::Notificare.authenticate_with = -> { true }` → allow

Configure in a host app initializer:
```ruby
ActiveJob::Notificare.authenticate_with = -> { current_user&.admin? }
```

The proc is evaluated via `instance_exec` inside the controller, so it has full access to session/request state.

**CSS**: the engine ships `app/assets/stylesheets/active_job/notificare/engine.css` (minimal, `nf-*` BEM prefix). The engine layout (`app/views/layouts/active_job/notificare/application.html.erb`) includes it via `stylesheet_link_tag "active_job/notificare/engine"` and loads `javascript_importmap_tags` if importmap-rails is available (for Turbo live updates on the show page).

**Production env test pattern**: since `Rails.stub` requires `minitest/mock` to be loaded (not auto-required by `rails/test_help`), the production-env auth test directly swaps `Rails.instance_variable_get(:@_env)` in a begin/ensure block.

### Notifications controller

`ActiveJob::Notificare::NotificationsController` (`app/controllers/active_job/notificare/notifications_controller.rb`) handles three routes:
- `PATCH /notifications/:id/read` → `#read` — calls `mark_read!`, responds with `read.turbo_stream.erb` which replaces the notification's turbo-frame with an updated card (unread modifier removed, "Mark as read" button gone)
- `PATCH /notifications/:id/dismiss` → `#dismiss` — calls `dismiss!`, responds with `dismiss.turbo_stream.erb` which removes the notification's turbo-frame from the DOM
- `DELETE /notifications` → `#clear` — collects `@notifications = visible.to_a` before `destroy_all`, responds with `clear.turbo_stream.erb` which emits a `turbo_stream.remove` for each collected frame

All three actions use `respond_to { |f| f.turbo_stream; f.html { head :ok } }`. Turbo automatically sends `Accept: text/vnd.turbo-stream.html` on `button_to` form submissions, so `format.turbo_stream` is selected without any extra attributes on the buttons. The `clear` action collects the relation into an array before `destroy_all` so the IDs are available when the stream view renders.

Authorization: `set_notification` scopes the find to `Notification.where(recipient: @current_recipient)`, returning `404` if the record doesn't belong to the current recipient. `set_current_recipient` returns `401` if the recipient cannot be resolved.

### Hotwire broadcast internals

- Both models use `broadcast_refresh_later_to` (async, via `Turbo::Streams::BroadcastStreamJob`). The `Turbo::ImmediateDebouncer` is active in test mode (set by the turbo-rails engine initializer), so the job is enqueued synchronously.
- **Event ordering gotcha**: in inline mode (`perform_enqueued_jobs { block }`), `enqueue.active_job` fires *after* `perform.active_job` (because `instrument` notifies subscribers after the block completes). This means the Projection's Execution row doesn't exist when `perform.active_job` fires for the same request. Always use `perform_enqueued_jobs` *without* a block in broadcast integration tests so the enqueue event fires first and the Execution/Notification rows exist when the job runs. Use two consecutive `perform_enqueued_jobs` calls when testing notification broadcasts: first to run the job (which queues `BroadcastStreamJob`), second to run the broadcast job.
- `assert_broadcasts(stream, count) { block }` from `ActionCable::TestHelper` takes the **unsigned** stream name (e.g., `"active_job_progress:#{job_id}"`), not the signed token from `Turbo::StreamsChannel.signed_stream_name`.

### Scaffold generator

`lib/generators/active_job/notificare/scaffold/scaffold_generator.rb` — `Rails::Generators::NamedBase` subclass invoked as:

```bash
rails generate active_job:notificare:scaffold ImportJob
# options:
#   --controller=MyImportsController  override the generated controller class name
#   --prefix=my_imports               override the route/view directory prefix
```

**What it does:**
1. Validates that the named class is loadable and includes `ActiveJob::Notificare`; prints an error and skips generation if not.
2. Generates `app/controllers/{prefix}_controller.rb` with `#index` (executions for this job class scoped to the recipient's notification history) and `#show` (single execution + per-run notifications).
3. Generates `app/views/{prefix}/index.html.erb` and `show.html.erb` using `active_job_notificare` / `active_job_notifications` helpers and `turbo_stream_from` subscriptions. All UI strings use `t()` dot-shorthand lookups — no hardcoded English in the templates.
4. Generates `config/locales/active_job_notificare_{prefix}.en.yml` with I18n keys for all view strings (title, status/started/completed labels, headings, empty states).
5. Prints a `resources :prefix, only: [:index, :show]` snippet to stdout — **never** mutates `config/routes.rb`.

**Naming convention:** `ImportJob` → `ImportsController`, `imports/` views, `imports_path`. The `--controller` flag overrides only the class name; the `--prefix` flag overrides the file path and route snippet; both flags are independent.

**`current_recipient`:** the generated controller defines a private `current_recipient` helper (exposed via `helper_method`) that defaults to `current_notificare_recipient || current_user`. Developers replace this with their own auth method.

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
- `ScaffoldDemoJob` — minimal job used for scaffold generator tests; includes `ActiveJob::Notificare`, `notify_on :completed, :failed`, one `step(:process, notify: :processed)`
- `HomeController` (`test/dummy/app/controllers/home_controller.rb`) — renders both view helpers for integration tests; accepts `user_id` and `job_id` params
- `ScaffoldDemosController` / `app/views/scaffold_demos/` — pre-generated scaffold (output of `rails generate active_job:notificare:scaffold ScaffoldDemoJob`) committed as the smoke test fixture; covered by `scaffold_smoke_test.rb`

**Dummy app browser JS setup**: the dummy app generator originally ran with `--skip-javascript`, so it had no `app/javascript/` or `config/importmap.rb`. Turbo wasn't loaded in the browser, which made `button_to` form submissions in the inbox do full-page navigation instead of in-place Turbo Stream swaps. Fixed by wiring up the standard Rails 8 importmap setup:
- `test/dummy/config/importmap.rb` pins `@hotwired/turbo-rails`, `@hotwired/stimulus`, `@hotwired/stimulus-loading`, plus `pin_all_from "app/javascript/controllers"`
- `test/dummy/app/javascript/application.js` imports `@hotwired/turbo-rails` and `controllers`
- `test/dummy/app/javascript/controllers/application.js` and `controllers/index.js` are the standard Stimulus boot files
- `test/dummy/app/views/layouts/application.html.erb` calls `<%= javascript_importmap_tags %>`

Without these, manual browser testing of the inbox actions appears broken even though the controller is doing the right thing — keep them in place when regenerating dummy app pieces.

`ProjectionTest` uses `include ActiveJob::TestHelper` and `perform_enqueued_jobs` (not `with_queue_adapter`, which doesn't exist in this Rails version) to drive integration paths.

Continuation step events are simulated in unit tests using `fake_step(name)` (a `Struct.new(:name)` double) passed to `instrument("step_started.active_job", ...)` / `instrument("step.active_job", job:, step:, interrupted: false)`. Note: `ActiveJob::Continuation` fires `step.active_job` (not `step_completed.active_job`) after each step block finishes; the payload includes `interrupted:` and `exception_object` (set by AS::Notifications when the block raises).

**Important**: `ActiveJob::Continuable#continue` rescues `StandardError` and calls `retry_job(wait: 5.seconds)` when `continuation.advanced?` is true (at least one step completed). This means a step-raising job does NOT re-raise in tests — `perform_enqueued_jobs` returns without error and the retry is scheduled in the future. Use plain `perform_enqueued_jobs` (no `assert_raises`) for jobs that fail mid-step after making progress.

**`enqueue.active_job` fires even when `around_enqueue` raises**: `ActiveSupport::Notifications.instrument` calls subscribers in `ensure`, so `enqueue.active_job` fires regardless of whether the enqueue block succeeds. This means the Projection creates an Execution row (and a `Turbo::Streams::BroadcastStreamJob` is enqueued) even for a job that raises `ArgumentError` due to a missing `recipient:`. When asserting that a specific job did NOT reach the adapter's enqueue, use `assert_no_enqueued_jobs(only: MyJobClass)` rather than `assert_no_enqueued_jobs` without the `only:` filter — the unfiltered form counts the `BroadcastStreamJob` and will fail spuriously.

### Failure & Recovery tests (`test/active_job/notificare/failure_recovery_test.rb`)

ERD §9 test suite (Ticket 13). Covers all numbered cases:

| Case | Test name prefix | What it tests |
|---|---|---|
| Worker kill | `worker_killed_mid-step:` | Simulate crash by never firing `perform.active_job`; assert no duplicate row, `progress_current` preserved, `current_step` accurate on resume |
| Concurrency | `concurrent_advance!` | 10 advance! threads + 1 status transition thread; final `progress_current` and `status` must both be consistent |
| Case 1 | `case_1_no_tracks_progress:` | Full lifecycle, zero rows in **both** tables |
| Case 2 | `case_2_indeterminate_progress:` | Lifecycle completes, `progress_total` stays nil (spinner mode) |
| Case 3 | `case_3_resume_reuses_row:` | Worker kill + re-enqueue reuses existing DB row; `started_at` preserved |
| Case 4 | `case_4_missing_recipient:` | `ArgumentError` raised; specific job class not present in adapter's `enqueued_jobs` |
| Case 5 | `case_5_manual_notify_after_completion:` | Notification row written; Turbo broadcast fires on recipient inbox stream |
| V1 behavior | `v1_duplicate_failed_notifications:` | Retried failure writes a second `failed` notification (documents current non-idempotent behavior) |

## Release process (Ticket 14)

Current version: `0.1.0.alpha.1` (prerelease). The gem is published to rubygems.org via Trusted Publishing (OIDC — no long-lived API keys).

### Files involved
- `lib/active_job/notificare/version.rb` — single source of truth for VERSION.
- `notificare.gemspec` — includes `spec.metadata` with `homepage_uri`, `source_code_uri`, `changelog_uri`, `bug_tracker_uri`, `rubygems_mfa_required: "true"`. `spec.files` allow-lists `lib/`, `app/`, `config/`, `LICENSE`, `README.md` only.
- `CHANGELOG.md` — Keep a Changelog format; top released heading must match `VERSION` (enforced by `test/active_job/notificare/version_test.rb`).
- `.github/workflows/release.yml` — triggers on `v*` tags; uses `rubygems/release-gem@v1` with `id-token: write` for the OIDC handshake.
- `LICENSE` — MIT, matches `spec.license`.

### To cut a new release
1. Bump `VERSION` in `version.rb` and add a heading in `CHANGELOG.md`.
2. `git commit -am "Release <version>"`, `git tag v<version>`, `git push origin main --tags`.
3. The workflow builds, exchanges the GitHub OIDC token, and pushes the gem automatically.

### Tests added
- `test/notificare_gemspec_test.rb` — asserts metadata keys, MIT license, ruby version, file exclusions.
- `test/active_job/notificare/version_test.rb` — adds rubygems prerelease shape regex test and changelog parity test.
- Build smoke test CI step in `ci.yml` — runs `gem build` + `gem unpack`, fails if forbidden dirs appear.

## Key conventions

- **No monkey-patching.** All hooks go through `ActiveSupport::Notifications`. If an upstream `ActiveJob::Continuation` event is missing, open a PR there.
- **`include ActiveJob::Notificare` is the opt-in.** It auto-includes `ActiveJob::Continuable`. `tracks_progress?` defaults to true after the include; `tracks_progress false` opts out without removing the include.
- **Rubocop uses `rubocop-rails-omakase`**, configured in `.rubocop.yml`. `test/dummy/` is excluded from linting.
- The `test/dummy/` Gemfile is separate from the gem's Gemfile; do not add test dependencies there. Adapter gems (`solid_queue`, `good_job`, `sidekiq`) belong in the **root Gemfile** (not the dummy app's) so they are loaded at Rails boot and their engines register autoload paths.
- **`turbo-rails` in the root Gemfile** (added for ticket 08). The gemspec does not declare it as a hard dependency; the models guard broadcast setup with `if defined?(Turbo::Broadcastable)` so the gem loads cleanly without turbo-rails.
- **Mount alias must be `notificare`**: host apps must mount the engine with `as: :notificare` — the installed partials reference `notificare.read_notification_path(...)`, `notificare.dismiss_notification_path(...)`, and `notificare.clear_notifications_path`. The `notificare_*_path` helpers in `ViewHelpers` (see above) provide an alternative for scaffold-generated or custom views that don't have the engine proxy in scope, but the installed partials still require the alias. Example: `mount ActiveJob::Notificare::Engine, at: "/notificare", as: :notificare`.
- **`ActiveJob::Notificare.current_recipient_proc`**: mattr on the module. Set in host app initializers to a lambda called via `instance_exec` in the engine's `NotificationsController` to resolve the current recipient. Defaults to `current_user` if the host app controller responds to it. Example: `ActiveJob::Notificare.current_recipient_proc = -> { current_user }`.
- **`ActiveJob::Notificare.authenticate_with`**: mattr on the module (default: `nil`). Set to a lambda evaluated via `instance_exec` in `ExecutionsController` to guard the admin UI. Without a proc in production, requests are rejected with 403. In non-production, requests are allowed without a proc (dev convenience). Example: `ActiveJob::Notificare.authenticate_with = -> { current_user&.admin? }`.
