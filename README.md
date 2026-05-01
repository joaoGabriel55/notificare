# Notificare

[![Gem Version](https://img.shields.io/badge/gem-v0.1.0-blue)](https://rubygems.org/gems/notificare)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.3-red)](https://www.ruby-lang.org/)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%208.1-CC0000)](https://rubyonrails.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Notificare** (Romanian: *"to notify"*) is a Rails engine that adds **persisted progress tracking** and a **durable notification inbox** to your ActiveJob jobs — with a Hotwire UI scaffold included.

It is a projection layer over [`ActiveJob::Continuation`](https://api.rubyonrails.org/classes/ActiveJob/Continuation.html) (shipped in Rails 8.1). Continuation owns execution and step-resume state; Notificare owns the persisted projection of progress, the notification inbox, and the realtime UI for both. **Step boundaries become a state machine that drives notifications** — no manual broadcast plumbing.

Two concepts, intentionally separate:

- **Progress** (`active_job_executions`) — *transient* live state of a running job (status, current step, current/total).
- **Notifications** (`active_job_notifications`) — *durable* user-facing records of job events: completed, failed, custom per-step milestones.

Mental model: *Active Storage, but for job progress — plus a small inbox for what those jobs report back to the user.*

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Getting Started](#getting-started)
- [Job DSL](#job-dsl)
  - [Progress tracking](#progress-tracking)
  - [Step DSL with notifications](#step-dsl-with-notifications)
  - [Lifecycle notifications (`notify_on`)](#lifecycle-notifications-notify_on)
  - [Manual notifications (`notify(...)`)](#manual-notifications-notify)
- [Recipient Enforcement](#recipient-enforcement)
- [View Helpers](#view-helpers)
- [Hotwire / Turbo Streams](#hotwire--turbo-streams)
- [Notification Actions (Inbox)](#notification-actions-inbox)
- [Configuration](#configuration)
- [Internationalization (I18n)](#internationalization-i18n)
- [Styling](#styling)
- [Resume Semantics](#resume-semantics)
- [Adapter Compatibility](#adapter-compatibility)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **One opt-in seam** — `include ActiveJob::Notificare` is everything you need; it auto-includes `ActiveJob::Continuable`.
- **Persisted progress** — every running job gets a row you can query, render, and update in realtime.
- **Step-driven notifications** — declare `step(:name, notify: :event)` and a notification row is written automatically on successful completion.
- **Lifecycle notifications** — `notify_on :completed, :failed` writes a notification when the job finishes (or fails).
- **Manual notifications** — call `notify(title:, description:, ...)` from anywhere inside `perform` for custom milestones.
- **Hotwire UI out of the box** — view helpers render progress bars and an inbox; updates broadcast over Turbo Streams.
- **Recipient enforcement** — jobs that produce notifications must be enqueued with `recipient:`; missing it raises before the adapter receives the job.
- **Resumable** — survives worker crashes via Continuation; the same execution row continues across resumes.
- **Adapter agnostic** — works with Solid Queue, GoodJob, Sidekiq, and any other ActiveJob adapter.
- **No monkey-patching** — everything hooks through `ActiveSupport::Notifications`.

---

## Requirements

- **Ruby** ≥ 3.3
- **Rails** ≥ 8.1 (for `ActiveJob::Continuation`)
- **`turbo-rails`** (optional, for realtime broadcasts; helpers degrade gracefully without it)

---

## Installation

Add to your `Gemfile`:

```ruby
gem "notificare"
```

Then bundle and run the install generator:

```bash
bundle install
bin/rails generate active_job:notificare:install
bin/rails db:migrate
```

The install generator creates:

- A migration for the `active_job_executions` and `active_job_notifications` tables.
- An initializer at `config/initializers/active_job_notificare.rb` with sensible defaults.

Mount the engine in `config/routes.rb` — **the `as: :notificare` alias is required**:

```ruby
mount ActiveJob::Notificare::Engine, at: "/active_job_notificare", as: :notificare
```

> The `as: :notificare` alias avoids a naming collision between the `active_job_notificare(execution)` view helper and the default route proxy. Internal partials reference `notificare.read_notification_path(...)`, so the alias is part of the public contract.

---

## Getting Started

A complete example:

```ruby
class ImportJob < ApplicationJob
  include ActiveJob::Notificare

  notify_on :completed, :failed

  def perform(import_id, recipient:)
    self.recipient = recipient
    @import = Import.find(import_id)

    step(:validate, notify: :validated) do
      @import.validate!
    end

    step(:import_rows) do |step|
      progress.total(@import.rows.count)
      @import.rows.find_each(start: step.cursor) do |row|
        row.import
        progress.advance!
        step.advance! from: row.id
      end
    end

    step :finalize
  end

  def finalize
    @import.finalize!
  end
end
```

Enqueue it with a `recipient:`:

```ruby
ImportJob.perform_later(import.id, recipient: current_user)
```

Render progress and the inbox in your views:

```erb
<%# In your "My Imports" page %>
<% @executions.each do |execution| %>
  <%= active_job_notificare(execution) %>
<% end %>

<%# In your app shell / header %>
<%= active_job_notifications(for: current_user) %>
```

That's it. Both helpers subscribe to Turbo Streams and update live as the job progresses and emits notifications.

---

## Job DSL

`include ActiveJob::Notificare` is the **single seam**. Including it:

- pulls in `ActiveJob::Continuable` (so `step` works),
- adds the `progress` handle,
- registers the `notify_on` and `notify(...)` primitives,
- enables enqueue-time `recipient:` enforcement when notifications are in play,
- defaults `tracks_progress?` to `true` (use `tracks_progress false` to opt out).

### Progress tracking

Inside `perform`, use the `progress` handle:

```ruby
def perform
  progress.total(items.count)   # optional — omit for an indeterminate spinner
  items.each do |item|
    item.process!
    progress.advance!           # advance by 1
  end
end
```

| Method | Description |
|---|---|
| `progress.total(n)` | Declare expected work for the in-progress execution row (optional; omit for indeterminate). |
| `progress.advance!(by = 1)` | Increment `progress_current` for the execution row. |

If `progress.total` is never called, the helper renders an indeterminate spinner.

### Step DSL with notifications

`step(name, notify: ..., **continuation_opts, &block)` wraps Continuation's `step` and lets you fire a per-step notification on **successful completion**:

```ruby
step(:validate, notify: :validated) do
  @import.validate!
end
# → on success, writes a Notification with event_type: "custom",
#   metadata: { "event" => "validated" },
#   title: "ImportJob: validated"

step(:charge, notify: { event: :charged, title: "Payment captured", description: "Card ending 4242" }) do
  @order.charge!
end
# → hash form lets you override title/description/metadata directly
```

**Failure semantics**: if the step raises (including `ActiveJob::Continuation::Interrupt`), no step-level notification is written. Lifecycle-level `failed` notifications still fire via `notify_on` if declared.

### Lifecycle notifications (`notify_on`)

Declare which lifecycle events auto-write notification rows:

```ruby
class ExportJob < ApplicationJob
  include ActiveJob::Notificare
  notify_on :completed, :failed

  def perform(report_id, recipient:)
    self.recipient = recipient
    # ...
  end
end
```

When the job finishes, a notification row is written with:

- `event_type: "completed"` or `"failed"`
- `title: "<JobClass> <event_type>"` (e.g. `"ExportJob completed"`)
- `description`: the exception message for `failed`, otherwise nil

### Manual notifications (`notify(...)`)

Call `notify(...)` from anywhere inside `perform` to write a custom notification on demand:

```ruby
def perform(recipient:)
  self.recipient = recipient

  do_some_work
  notify(
    title: "Halfway there",
    description: "Processed 500 of 1000 records",
    metadata: { batch: 1 },
    actions: [{ label: "View progress", url: "/imports/123" }]
  )
  do_more_work
end
```

This writes a row with `event_type: "custom"` directly — independent of lifecycle hooks, so it is safe to call before, during, or after step boundaries. If `self.recipient` is nil at write time, the call is silently skipped.

> **Heads-up:** the first `notify(...)` call flips the job class into "uses notifications" mode, so subsequent enqueues are subject to recipient enforcement. To opt in eagerly (so the very *first* enqueue raises if `recipient:` is missing), call `uses_notify!` at class definition.

---

## Recipient Enforcement

Jobs that opt into notifications — via `notify_on`, any `step(notify:)`, or `uses_notify!` — **must** be enqueued with a `recipient:` keyword argument:

```ruby
ImportJob.perform_later(import.id, recipient: current_user)  # ✅
ImportJob.perform_later(import.id)                           # ❌ raises ArgumentError
```

The error is raised by an `around_enqueue` callback **before** the queue adapter receives the job. `recipient` accepts any object responding to `to_global_id` — typically an Active Record model.

Jobs that don't opt into notifications are unaffected; they can be enqueued with any signature.

---

## View Helpers

Two helpers, auto-included into `ActionView::Base` by the engine:

### `active_job_notificare(execution)`

Renders a progress widget for a single `Execution`:

```erb
<%= active_job_notificare(execution) %>
```

- **Determinate** (when `progress_total` is set): a `<progress>` element with a `current/total` label and a percentage.
- **Indeterminate** (when `progress_total` is nil): a CSS spinner.
- Shows `current_step` if present.
- Subscribes to `["active_job_progress", execution.job_id]`.

### `active_job_notifications(for: recipient)`

Renders the recipient's inbox of *visible* (not dismissed) notifications:

```erb
<%= active_job_notifications(for: current_user) %>
```

- Lists notifications newest-first.
- Unread items get a `notificare-notification--unread` modifier class.
- Each item has **Mark as read** and **Dismiss** buttons.
- A **Clear all** action removes every visible notification for the recipient.
- Custom per-notification `actions:` are rendered as links.
- Subscribes to `["active_job_notifications", recipient.to_gid_param]`.

---

## Hotwire / Turbo Streams

Both models include `Turbo::Broadcastable` (when `turbo-rails` is loaded) and call `broadcast_refresh_later_to` on every change. **You never need to write `broadcast_*` calls in user code.**

The two stable stream names are part of the public API — host apps can subscribe to them directly via `turbo_stream_from`:

| Surface | Stream identifier |
|---|---|
| Execution progress | `["active_job_progress", execution.job_id]` |
| Notifications inbox | `["active_job_notifications", recipient.to_gid_param]` |

Stream names are rooted in the table-name domain (not the gem name), so future renames don't churn deployed Turbo subscriptions.

---

## Notification Actions (Inbox)

The engine exposes three routes for inbox interactions, all scoped to the current recipient:

| Verb | Path | Action | Description |
|---|---|---|---|
| `PATCH` | `/notifications/:id/read` | `read` | Mark a single notification as read. |
| `PATCH` | `/notifications/:id/dismiss` | `dismiss` | Dismiss (hide) a notification. |
| `DELETE` | `/notifications` | `clear` | Dismiss all visible notifications for the recipient. |

Authorization is automatic: the controller scopes `find` to `Notification.where(recipient: current_recipient)`. A request for someone else's notification returns **404**; an unresolved recipient returns **401**.

---

## Configuration

### Resolving the current recipient

The notifications controller needs to know who the "current recipient" is. By default, it calls `current_user` if the host application controller responds to it. To customize, set a proc in an initializer:

```ruby
# config/initializers/active_job_notificare.rb
ActiveJob::Notificare.current_recipient_proc = -> { current_account }
```

The proc is evaluated via `instance_exec` inside the engine's controller, so it has access to host-app session state.

### Generated initializer

The install generator creates a stub initializer with commented-out options:

```ruby
# ActiveJob::Notificare.configure do |config|
#   config.execution_retention   = 7.days   # or nil to keep forever
#   config.broadcast_progress    = true
#   config.broadcast_notifications = true
#   config.mount_path            = "/notificare"
# end
```

---

## Internationalization (I18n)

All UI strings in the inbox partial use `t()` lookups. Override any key in your host app's locale files.

| Key | Default (en) |
|---|---|
| `active_job.notificare.notifications.clear_all` | `"Clear all"` |
| `active_job.notificare.notifications.mark_as_read` | `"Mark as read"` |
| `active_job.notificare.notifications.dismiss` | `"Dismiss"` |

```yaml
# config/locales/pt-BR.yml
pt-BR:
  active_job:
    notificare:
      notifications:
        clear_all: "Limpar tudo"
        mark_as_read: "Marcar como lida"
        dismiss: "Dispensar"
```

---

## Styling

The gem ships **no CSS** — it renders semantic markup with a stable `notificare-*` class hierarchy you can style however you like.

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

The inbox wrapper also has the DOM id `#active_job_notifications` for `turbo_stream` targeting.

---

## Resume Semantics

When a worker is killed mid-step, `ActiveJob::Continuation` re-enqueues the job with the same `job_id`. The projection looks up the existing execution row by `job_id` and continues updating it:

- **No duplicate row** is created on resume (`find_or_create_by!` + `RecordNotUnique` rescue).
- **`progress_current` and `started_at` are preserved** across the resume.
- Any **stale `error` is cleared** when the job restarts.
- There is **no `continuation_state` column** — Continuation owns that state itself; duplicating it would create an unsolvable consistency problem.

> **Note (v1):** lifecycle notifications are not deduplicated across retries. A job that fails, retries, and fails again may produce multiple `failed` notifications. This is documented behavior; idempotency is on the roadmap.

---

## Adapter Compatibility

Queue-adapter agnostic. Tested against:

- **Solid Queue** (first-class)
- **GoodJob**
- **Sidekiq** (via ActiveJob)

Works with any ActiveJob adapter that integrates with `ActiveSupport::Notifications` (which is essentially all of them).

---

## Testing

Notificare integrates with Rails' standard test helpers. Use `ActiveJob::TestHelper#perform_enqueued_jobs` to drive jobs end-to-end:

```ruby
class ImportJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "writes execution and notification rows" do
    perform_enqueued_jobs do
      ImportJob.perform_later(imports(:big).id, recipient: users(:alice))
    end

    execution = ActiveJob::Notificare::Execution.last
    assert_equal "completed", execution.status

    notification = ActiveJob::Notificare::Notification.last
    assert_equal "completed", notification.event_type
    assert_equal users(:alice), notification.recipient
  end
end
```

> **Heads-up — broadcast tests:** in inline mode, `enqueue.active_job` fires *after* `perform.active_job`. When asserting broadcasts, call `perform_enqueued_jobs` **without a block** so the enqueue event lands first and rows exist when the job runs. Use two consecutive calls when testing notification broadcasts: the first runs the job (which queues `BroadcastStreamJob`), the second runs the broadcast job.

### Running the gem's own test suite

```bash
bundle exec rake test           # full suite (enforces 95% coverage)
bundle exec rubocop             # lint
bundle exec rubocop -a          # autocorrect
```

---

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/joaoGabriel55/notificare.

1. Fork the repo and create your branch from `main`.
2. Run `bundle install` and `bundle exec rake test` to make sure the suite is green.
3. Add tests for any new behavior — coverage must stay ≥ 95%.
4. Run `bundle exec rubocop` before committing.
5. Open a PR with a clear description of the change.

**Design rule:** prefer adding less. The gem's public API is intentionally tiny; anything new should be designed as if it might one day be absorbed into ActiveJob core. *"Would this feel reasonable in Rails itself?"* If not, simplify or remove.

---

## License

Released under the [MIT License](LICENSE).

---

## Inspirations

Active Storage. Action Mailbox. Solid Queue. Mission Control Jobs.
