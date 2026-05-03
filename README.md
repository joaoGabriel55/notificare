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
- [Admin UI (Mounted Engine)](#admin-ui-mounted-engine)
- [Scaffold Generator](#scaffold-generator)
- [Configuration](#configuration)
- [Internationalization (I18n)](#internationalization-i18n)
- [Customizing the markup](#customizing-the-markup)
- [Styling](#styling)
- [Resume Semantics](#resume-semantics)
- [Adapter Compatibility](#adapter-compatibility)
- [Testing](#testing)
- [Playing with the gem locally](#playing-with-the-gem-locally)
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
- **An ActiveJob queue adapter** (Solid Queue, GoodJob, Sidekiq, etc.). The default `:async` adapter is fine for development.
- **`turbo-rails`** (recommended). Without it, the model-level `Turbo::Broadcastable` hooks are skipped and the gem still works — but live progress, live inbox, and inline button responses (Mark as read, Dismiss, Clear all) all depend on Turbo. The view helpers degrade gracefully (no live updates), but inbox button submissions will navigate the browser unless Turbo is loaded on the page.
- **Turbo loaded in the browser.** Having `turbo-rails` in your Gemfile is not enough; your application layout must execute the Turbo runtime. In a default Rails 8 app this is automatic via importmap-rails (`<%= javascript_importmap_tags %>` in `app/views/layouts/application.html.erb` plus `import "@hotwired/turbo-rails"` in `app/javascript/application.js`). If you skipped JavaScript when generating the app, set this up before mounting the engine.
- **Action Cable** configured (it is by default in Rails 8). Required for `turbo_stream_from` subscriptions used by the progress and inbox helpers.

---

## Installation

### 1. Add the gem

```ruby
# Gemfile
gem "notificare"
gem "turbo-rails"  # recommended — enables live broadcasts and inline inbox actions
```

```bash
bundle install
```

### 2. Run the install generator

```bash
bin/rails generate active_job:notificare:install
bin/rails db:migrate
```

The generator creates:

| File | Purpose |
|---|---|
| `db/migrate/<ts>_create_active_job_notificare_tables.rb` | Creates `active_job_executions` and `active_job_notifications` tables (plus indexes for `job_id`, `recipient`, and `read_at`). |
| `config/initializers/active_job_notificare.rb` | Empty initializer — uncomment knobs you want to override (see [Configuration](#configuration)). |
| `app/views/active_job/notificare/_progress.html.erb` | Progress widget partial. Owned by your app — customize freely. |
| `app/views/active_job/notificare/_notifications.html.erb` | Inbox wrapper partial (clear-all button + iteration). |
| `app/views/active_job/notificare/_notification.html.erb` | Single notification card partial (wrapped in `turbo_frame_tag`). |

The generator copies the partials into your app so the gem never ships markup that overrides yours. Edit them to match your design system; the underlying controllers, models, and Turbo Stream responses keep working as long as you keep the DOM ids and frame ids intact (see [Customizing the markup](#customizing-the-markup)).

### 3. Mount the engine

In `config/routes.rb`:

```ruby
mount ActiveJob::Notificare::Engine, at: "/notificare", as: :notificare
```

The `as: :notificare` alias is **required** — it avoids a naming collision between the `active_job_notificare(execution)` view helper and the default route proxy. Internal partials reference `notificare.read_notification_path(...)`, `notificare.dismiss_notification_path(...)`, and `notificare.clear_notifications_path`, so the alias is part of the public contract.

The mount point itself (`/notificare`) is arbitrary — pick anything you like.

### 4. Make sure Turbo is loaded in the browser

If you generated your Rails app with `--skip-javascript`, the inbox actions will do full-page navigation instead of in-place updates. Verify your layout includes:

```erb
<%# app/views/layouts/application.html.erb %>
<%= javascript_importmap_tags %>
```

…and your `app/javascript/application.js` imports Turbo:

```javascript
import "@hotwired/turbo-rails"
```

That's it. You're ready to wire up a job.

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
| `progress.advance!(by = 1)` | Increment `progress_current` on the execution row by `by` (defaults to 1). |

If `progress.total` is never called, the helper renders an indeterminate spinner. If `progress.total` is set, the helper renders a `<progress>` element with a `current/total` label and a percentage.

#### Opting out

`include ActiveJob::Notificare` defaults `tracks_progress?` to `true`. To opt a single job out of all projection writes (no execution row, no notifications) without removing the include — useful when you still want the DSL/notify helpers available conditionally — declare:

```ruby
class QuietJob < ApplicationJob
  include ActiveJob::Notificare
  tracks_progress false
end
```

### Step DSL with notifications

`step(name, notify: ..., **continuation_opts, &block)` wraps Continuation's `step` and lets you fire a per-step notification on **successful completion**:

```ruby
# Symbol form — minimal
step(:validate, notify: :validated) do
  @import.validate!
end
# → on success, writes a Notification with:
#     event_type: "custom"
#     metadata:   { "event" => "validated" }
#     title:      "ImportJob: validated"
#     description: nil

# Hash form — override anything
step(:charge, notify: { event: :charged, title: "Payment captured", description: "Card ending 4242", metadata: { amount_cents: 4999 } }) do
  @order.charge!
end
# → on success, writes a Notification with:
#     event_type: "custom"
#     metadata:   { "event" => "charged", "amount_cents" => 4999 }
#     title:      "Payment captured"
#     description: "Card ending 4242"

# No notify: kwarg — just a Continuation step boundary
step :finalize
```

The block receives Continuation's `step` object. Use it for resumable cursors so a worker crash mid-step picks up where it left off:

```ruby
step(:import_rows) do |step|
  progress.total(@import.rows.count)
  @import.rows.find_each(start: step.cursor) do |row|
    row.import
    progress.advance!
    step.advance! from: row.id      # checkpoints the cursor for resume
  end
end
```

**Failure semantics:** if the step raises (including `ActiveJob::Continuation::Interrupt`), no step-level notification is written. Lifecycle-level `failed` notifications still fire via `notify_on` if declared.

**Recipient enforcement:** declaring any `step(notify: ...)` flips the class into [recipient-required mode](#recipient-enforcement). Subsequent `perform_later` calls without a `recipient:` kwarg will raise `ArgumentError` before the job is enqueued.

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
    actions: [
      { label: "View progress", url: "/imports/123" },
      { label: "Cancel",        url: "/imports/123/cancel" }
    ]
  )
  do_more_work
end
```

**Signature:** `notify(title:, description: nil, metadata: {}, actions: [])`

| Keyword | Required? | Description |
|---|---|---|
| `title` | yes | Plain text, rendered as `<strong>` in the notification card. |
| `description` | no | Plain text body, rendered as `<p>` only when present. |
| `metadata` | no | Free-form hash stored as JSON. Keys you write are preserved verbatim; useful for app-specific filtering. |
| `actions` | no | Array of `{ label:, url: }` hashes. Each one is rendered as an `<a>` inside the card's actions container. |

This writes a row with `event_type: "custom"` directly — independent of lifecycle hooks — so it is safe to call before, during, or after step boundaries, and any number of times per job. If `self.recipient` is nil at write time, the call is silently skipped (no exception, no row).

> **Heads-up:** the first `notify(...)` call flips the job class into "uses notifications" mode, so subsequent enqueues are subject to recipient enforcement. To opt in eagerly (so the very *first* enqueue raises if `recipient:` is missing), call `uses_notify!` at class definition:
>
> ```ruby
> class HalfwayPingJob < ApplicationJob
>   include ActiveJob::Notificare
>   uses_notify!   # makes recipient: required from the very first perform_later
> end
> ```

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

The following helpers are auto-included into `ActionView::Base` by the engine:

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
- Each item has **Mark as read** and **Dismiss** buttons; each card is wrapped in a `<turbo-frame>` so actions update only that card inline — no page redirect.
- A **Clear all** action removes every visible notification for the recipient via Turbo Stream, with no redirect.
- Custom per-notification `actions:` are rendered as links.
- Subscribes to `["active_job_notifications", recipient.to_gid_param]`.

### Route path helpers

Three context-aware helpers are available for building custom views or scaffold-generated pages that need to link to engine notification actions without relying on the `notificare.` engine proxy:

| Helper | Resolves to |
|---|---|
| `notificare_read_notification_path(notification)` | `PATCH /notificare/notifications/:id/read` |
| `notificare_dismiss_notification_path(notification)` | `PATCH /notificare/notifications/:id/dismiss` |
| `notificare_clear_notifications_path` | `DELETE /notificare/notifications` |

In engine views these call the bare route helper directly; in host-app views they fall back to `url_for` with the full controller path, so they work regardless of how the engine is mounted. The installed partials (`_notifications.html.erb`, `_notification.html.erb`) still use `notificare.X` directly and require the `as: :notificare` mount alias.

---

## Hotwire / Turbo Streams

Both models include `Turbo::Broadcastable` (when `turbo-rails` is loaded) and call `broadcast_refresh_later_to` on every change. **You never need to write `broadcast_*` calls in user code.** A row create or update enqueues `Turbo::Streams::BroadcastStreamJob`, which sends a `<turbo-stream>` over Action Cable to every browser subscribed to that stream.

The two stable stream names are part of the public API — host apps can subscribe to them directly via `turbo_stream_from`:

| Surface | Stream identifier | When it broadcasts |
|---|---|---|
| Execution progress | `["active_job_progress", execution.job_id]` | After every `Execution` create/update (status changes, `progress_current` ticks, `current_step` mirrors). |
| Notifications inbox | `["active_job_notifications", recipient.to_gid_param]` | After every `Notification` create/update (new row, `mark_read!`, `dismiss!`). |

Stream names are rooted in the table-name domain (not the gem name), so future renames don't churn deployed Turbo subscriptions.

### What needs to be loaded

The view helpers emit `<turbo-cable-stream-source>` (via `turbo_stream_from`) and `<turbo-frame>` elements. For these to do anything in the browser:

1. **`turbo-rails`** must be in your Gemfile. Without it, the gem skips the broadcast hooks and no streams fire.
2. **Turbo must be imported** in your `app/javascript/application.js` (`import "@hotwired/turbo-rails"`) and the layout must execute it (`<%= javascript_importmap_tags %>`).
3. **Action Cable** must be running. In development, `bin/dev` (or `rails server`) handles this automatically when Turbo is loaded.

If any of those is missing, the helpers still render correctly on first load — you just won't see live updates, and the inbox buttons will navigate the browser instead of swapping in place.

### Subscribing manually

If you want the stream subscription without the gem's default markup (e.g. to render notifications inside your own component), subscribe directly:

```erb
<%= turbo_stream_from "active_job_notifications", current_user.to_gid_param %>
<div id="my_inbox">
  <%# render however you like; updates arrive as turbo_stream broadcasts %>
</div>
```

---

## Notification Actions (Inbox)

The engine exposes three routes for inbox interactions, all scoped to the current recipient. Paths below are **relative to the engine mount point** (e.g. with `mount … at: "/notificare"`, the read path is `/notificare/notifications/:id/read`).

| Verb | Path | Helper | Action | Description |
|---|---|---|---|---|
| `PATCH` | `/notifications/:id/read` | `notificare.read_notification_path(id)` | `read` | Mark a single notification as read. |
| `PATCH` | `/notifications/:id/dismiss` | `notificare.dismiss_notification_path(id)` | `dismiss` | Dismiss (hide) a single notification. |
| `DELETE` | `/notifications` | `notificare.clear_notifications_path` | `clear` | Dismiss every visible notification for the current recipient. |

All three actions respond with Turbo Stream content — no redirect, no full-page reload:

| Action | Turbo Stream effect | Template |
|---|---|---|
| `read` | Replaces the notification's `<turbo-frame>` with the updated card (unread modifier removed, "Mark as read" button hidden) | `read.turbo_stream.erb` |
| `dismiss` | Removes the notification's `<turbo-frame>` from the DOM | `dismiss.turbo_stream.erb` |
| `clear` | Removes every visible notification frame in one response | `clear.turbo_stream.erb` |

> **Why does my "Mark as read" button navigate to `/notifications/1/read`?** That happens when Turbo isn't loaded in the browser. `button_to` submits a normal form, the browser follows the response, and the controller's HTML branch returns `head :ok` (a blank page at that URL). See [Requirements](#requirements) — `import "@hotwired/turbo-rails"` and `<%= javascript_importmap_tags %>` are both needed.

**Authorization:** the controller scopes `find` to `Notification.where(recipient: current_recipient)`. A request for someone else's notification returns **404**; an unresolved recipient returns **401**.

**CSRF:** the engine's `ApplicationController` calls `protect_from_forgery with: :exception`. `button_to` includes the CSRF token automatically; if you build a custom form, include `<%= csrf_meta_tags %>` in your layout.

---

## Admin UI (Mounted Engine)

The engine ships a minimal admin status page accessible at the engine's mount point (e.g. `/notificare`).

### Executions index

`GET /` (root) and `GET /executions` — paginated list of all executions. Filter by status or job class via query params:

```
/active_job_notificare/executions?status=failed
/active_job_notificare/executions?job_class=ImportJob
/active_job_notificare/executions?status=running&job_class=ExportJob
```

Displays status badge, job class, job ID, current step, progress fraction, start/finish timestamps. Paginates at 25 rows per page.

### Execution show

`GET /executions/:id` — single execution detail with:

- Status, job ID, current step, started/completed timestamps, error message.
- **Live progress widget** — the same `active_job_notificare(execution)` helper used in your own views, subscribing to the Turbo Stream channel. Updates automatically without a page refresh while the job is running.
- **Tied notifications** — all `Notification` rows written for the same `job_id`, newest-first.

### Authentication

The admin UI is protected by `ActiveJob::Notificare.authenticate_with`. Configure it in an initializer:

```ruby
# config/initializers/active_job_notificare.rb
ActiveJob::Notificare.authenticate_with = -> { current_user&.admin? }
```

The lambda is evaluated via `instance_exec` inside the `ExecutionsController`, so it has full access to session state (params, cookies, `current_user`, etc.).

**Fail-safe default:** if `authenticate_with` is not configured and the environment is `production`, every request returns `403 Forbidden`. In development/test, unauthenticated access is allowed for convenience.

| Scenario | Result |
|---|---|
| `authenticate_with` not set + production | `403 Forbidden` |
| `authenticate_with` not set + non-production | allowed |
| `authenticate_with = -> { false }` | `403 Forbidden` |
| `authenticate_with = -> { true }` | allowed |

### Styling

The engine ships a small stylesheet (`active_job/notificare/engine.css`) included via the engine's own layout. The layout also loads `javascript_importmap_tags` if `importmap-rails` is present, enabling Turbo live updates on the show page. Host apps that use a different JS bundler should ensure Turbo is loaded on the page before visiting the admin UI.

---

## Scaffold Generator

For building your own product pages (e.g. "My Imports") that embed live progress and notifications, the scaffold generator creates a controller and views wired to Turbo Streams:

```bash
bin/rails generate active_job:notificare:scaffold ImportJob
```

For `ImportJob`, this creates:

| File | Purpose |
|---|---|
| `app/controllers/imports_controller.rb` | `#index` (executions scoped to the current recipient's notification history) and `#show` (detail + per-run notifications). |
| `app/views/imports/index.html.erb` | List of executions with live `active_job_notificare` progress widgets and the full notification inbox. All strings are I18n `t()` lookups. |
| `app/views/imports/show.html.erb` | Execution detail with live progress widget and per-run notification list, both subscribed via `turbo_stream_from`. All strings are I18n `t()` lookups. |
| `config/locales/active_job_notificare_imports.en.yml` | English translations for all view strings (titles, labels, headings, empty states). Override keys in your own locale files. |

A routes snippet is **printed to stdout** — the generator never modifies `config/routes.rb`. Paste it yourself:

```ruby
# config/routes.rb
resources :imports, only: [:index, :show]
```

### Naming convention

`ImportJob` → `ImportsController`, `imports/` views, `imports_path`. The convention strips the `Job` suffix and pluralizes:

| Argument | Controller | Views directory | Locale file | Route helpers |
|---|---|---|---|---|
| `ImportJob` | `ImportsController` | `app/views/imports/` | `active_job_notificare_imports.en.yml` | `imports_path`, `import_path(id)` |
| `ReportExportJob` | `ReportExportsController` | `app/views/report_exports/` | `active_job_notificare_report_exports.en.yml` | `report_exports_path`, `report_export_path(id)` |

### Override flags

```bash
# Override just the controller class name
bin/rails generate active_job:notificare:scaffold ImportJob --controller=MyImportsController

# Override the route/view prefix
bin/rails generate active_job:notificare:scaffold ImportJob --prefix=my_imports

# Both flags are independent
bin/rails generate active_job:notificare:scaffold ImportJob \
  --controller=MyImportsController --prefix=my_imports
```

### `current_recipient`

The generated controller exposes a `current_recipient` helper method (via `helper_method`) used by both actions and views to scope executions and notifications:

```ruby
private

# TODO: replace with however your app exposes the signed-in user/account.
def current_recipient
  current_notificare_recipient || current_user
end
helper_method :current_recipient
```

Replace the body with whatever your app uses (`current_account`, `Current.user`, etc.).

### Validation

The generator validates that the named class exists and includes `ActiveJob::Notificare`. If the class is missing or doesn't include the concern, it prints an error and creates no files:

```
$ bin/rails generate active_job:notificare:scaffold String
error  String does not include ActiveJob::Notificare.
       Add `include ActiveJob::Notificare` to the job class and re-run the generator.
```

---

## Configuration

The gem exposes three module-level knobs, all `mattr_accessor` on `ActiveJob::Notificare`:

| Knob | Default | Purpose |
|---|---|---|
| `ActiveJob::Notificare.authenticate_with` | `nil` | Lambda evaluated via `instance_exec` in `ExecutionsController` to guard the admin UI. Nil in production denies access. |
| `ActiveJob::Notificare.current_recipient_proc` | `nil` | Lambda evaluated via `instance_exec` inside the engine's controllers to resolve the current recipient. Falls back to `current_notificare_recipient`, then `current_user`. |
| `ActiveJob::Notificare.parent_controller` | `"ApplicationController"` | The constant name (string) the engine's `ApplicationController` inherits from. Set this if your app routes everything through a custom base controller (e.g. `Api::BaseController`). |

Set them in `config/initializers/active_job_notificare.rb`.

### Resolving the current recipient

The notifications controller needs to know who the "current recipient" is for every request. The engine's `ApplicationController` inherits from `::ApplicationController` by default, so the simplest approach is to define `current_notificare_recipient` in your own `ApplicationController`:

```ruby
# app/controllers/application_controller.rb
def current_notificare_recipient
  current_user  # or however you expose the signed-in user
end
```

The engine controller inherits this method and calls it automatically. If neither `current_notificare_recipient` nor `current_user` is defined, the engine raises `NotImplementedError` with a clear message pointing you here.

**Alternative — proc in an initializer:**

If you prefer not to touch your `ApplicationController`, set a proc instead. It is evaluated via `instance_exec` inside the engine's controller so it has full access to session state:

```ruby
# config/initializers/active_job_notificare.rb
ActiveJob::Notificare.current_recipient_proc = -> { current_account }
```

**Advanced — custom parent controller:**

If your app uses a non-standard base controller (e.g. `Api::BaseController`), tell the engine to inherit from it instead of `ApplicationController`:

```ruby
# config/initializers/active_job_notificare.rb
ActiveJob::Notificare.parent_controller = "Api::BaseController"
```

The engine's controllers will then inherit from that class, picking up any auth helpers it defines.

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

## Customizing the markup

The install generator copies three partials into your app under `app/views/active_job/notificare/`. They are yours — edit them freely. The contracts the gem relies on are minimal:

| Partial | Required DOM hooks | Why |
|---|---|---|
| `_progress.html.erb` | `<%= turbo_stream_from "active_job_progress", execution.job_id %>` | Subscribes the widget to the execution's broadcast channel. |
| `_notifications.html.erb` | `<%= turbo_stream_from "active_job_notifications", recipient.to_gid_param %>`; outer wrapper `id="active_job_notifications"` | Subscribes the inbox; the wrapper id is the target Turbo refreshes broadcast to. |
| `_notification.html.erb` | `<%= turbo_frame_tag dom_id(notification) do %>…<% end %>` | The frame id (`active_job_notificare_notification_<id>`) is what the controller's `read.turbo_stream.erb` and `dismiss.turbo_stream.erb` target by id. |

Inside those constraints, structure the markup however you like — Tailwind classes, your own design system, ViewComponent wrappers, anything. The controllers, models, and Turbo Stream responses don't read your CSS classes.

If you need to render the inbox somewhere unusual (e.g. a sidebar that's only visible after a click), call the helper anyway — `<turbo-cable-stream-source>` works fine while hidden.

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

Queue-adapter agnostic. Tested against Solid Queue, GoodJob, and Sidekiq in the CI matrix (Ruby 3.3 and 3.4):

| Adapter | Database | Notes |
|---|---|---|
| **Solid Queue** | Postgres | Queue persisted in DB; drain via `SolidQueue::ReadyExecution` |
| **GoodJob** | Postgres | Queue persisted in DB; drain via `GoodJob.perform_inline` |
| **Sidekiq** | SQLite (any) | Queue in Redis; drained via `Sidekiq.testing!(:fake)` + `drain_all` |

Works with any ActiveJob adapter that integrates with `ActiveSupport::Notifications` (which is essentially all of them). The gem does not branch on adapter type anywhere in `lib/` — the AS::Notifications projection is identical regardless of which adapter runs the job.

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

## Playing with the gem locally

The `test/dummy/` directory is a full Rails 8.1 app wired up with Notificare, Solid Queue, and Turbo. It is the fastest way to explore the gem without a host app.

### Setup

```bash
cd test/dummy
bundle install
bin/rails db:migrate
bin/rails db:setup   # create + migrate + seed
```

The seed script creates two users (Alice and Bob) with a set of executions and notifications covering every state: completed, running, failed, enqueued, unread, read, and custom step-level.

### Start the server

```bash
bin/rails server
```

Then open:

- **Admin UI** — <http://localhost:3000/notificare> — paginated executions list and per-execution detail with live progress.
- **Alice's inbox** — <http://localhost:3000/home?user_id=1>
- **Bob's inbox** — <http://localhost:3000/home?user_id=2>

The home page renders `active_job_notificare` (progress widget) and `active_job_notifications` (inbox) for the given user.

### Enqueue a job from the console

```bash
bin/rails console
```

```ruby
alice = User.first

# Lifecycle notifications (completed + failed)
NotifyOnTestJob.perform_later(recipient: alice)
FailingNotifyOnTestJob.perform_later(recipient: alice)

# Step-level notifications with progress tracking
StepNotifyTestJob.perform_later(recipient: alice)

# Manual notify() call mid-job
ManualNotifyTestJob.perform_later(recipient: alice)
```

Jobs run inline in development (`:async` adapter). Refresh the inbox page to see new notifications land.

### Reset to a clean slate

```bash
bin/rails db:seed:replant   # truncate + re-seed
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
