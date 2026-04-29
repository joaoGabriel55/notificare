# Engineering Requirements Document — ActiveJob Progress

**Working name:** `koraci` (Bosnian for "steps")

**Tagline:** First-class progress tracking and a notification inbox for Active Job.

**Positioning (one line):** A projection layer over `ActiveJob::Continuable`. Continuable owns execution and continuation state; this gem owns the persisted projection of progress, a small notification inbox primitive, and the Hotwire UI for both.

---

## 1. Product Philosophy

Aligned with Rails sensibilities:

- Rails-native, database-backed, Hotwire-first
- Convention over configuration, minimal public API, few concepts
- Composes with existing Rails features; easy to delete if not needed
- Designed as if it might one day live in Rails itself

Avoid: enterprise orchestration vocabulary, YAML DSLs, DAG engines, Temporal-like ambitions, configuration sprawl.

> **Litmus test for every feature:** "Would this feel reasonable in Rails itself?" If not, simplify or remove.

Mental model: *Active Storage, but for job progress — plus a small inbox for what those jobs report back to the user.*

---

## 2. Problem Statement

`ActiveJob::Continuable` provides resumable jobs. It does **not** provide:

- a persisted, queryable projection of running-job state
- a place to record durable, user-facing notifications when those jobs finish (or hit milestones)
- realtime UI for either of those things

Long-running product operations — file uploads, imports, exports, batch processing — need both: a *live* progress view while running, and a *durable* notification afterward ("your import finished," "your export failed"). Rails has the primitives. This gem fills the gap with two small concepts and nothing more.

---

## 3. The Two Concepts

The gem deliberately exposes **two** concepts, not one:

### Progress (transient)

State about a *currently running* job. Lives as long as the job is interesting to look at. Source of truth for progress bars, current-step indicators, spinners.

Stored in `active_job_executions`.

### Notifications (durable)

A user-facing record that *something happened* — usually that a job completed or failed, but the gem also exposes a manual API so developers can write notifications for any milestone they care about. Read/unread, dismissible, with optional custom actions.

Stored in `active_job_notifications`.

These are intentionally separate. Progress is "is the thing still going?" Notifications are "here's what happened." Trying to unify them (one row that's both a live progress bar and a durable inbox entry) is the kind of clever abstraction the litmus test rejects.

---

## 4. The Two UI Surfaces

### Surface 1 — Mounted engine (admin-flavored)

```ruby
mount ActiveJob::Progress::Engine => "/job_progress"
```

One per app. For developers and ops. Lists recent executions, shows individual execution status. Spirit of Mission Control Jobs. Path defaults to `/job_progress` to avoid colliding with Mission Control if both are mounted.

### Surface 2 — Embedded product UI

The developer drops progress widgets and notification inboxes into their *own* product pages — a "My Imports" page, a file upload component, a checkout-processing screen. The gem provides view helpers for the common cases and a scaffold generator for the rest.

The scaffold generator (§8) is mostly about Surface 2.

---

## 5. Public API

### Job DSL

```ruby
class ImportJob < ApplicationJob
  include ActiveJob::Continuable
  include ActiveJob::Progress

  tracks_progress
  notify_on :completed, :failed

  step :import_rows do |step|
    progress.total(rows.count)

    rows.each do |row|
      import(row)
      progress.advance!
    end
  end
end
```

Surface area for job authors:

- `tracks_progress` — opt in to the execution projection and broadcasting
- `progress.total(n)` — declare expected work (optional; omit for indeterminate)
- `progress.advance!(by = 1)` — increment within a Continuable step
- `notify_on :completed, :failed` — declarative auto-notifications on lifecycle events
- `notify(title:, description:, metadata: {}, actions: [])` — manual notification from anywhere inside the job, for custom milestones

Jobs that opt into notifications (`notify_on` or any call to `notify`) must receive a `recipient:` keyword argument at enqueue time:

```ruby
ImportJob.perform_later(file, recipient: current_user)
```

`recipient` accepts any object responding to `to_global_id` (typically an Active Record model). Enqueuing such a job without `recipient:` raises `ArgumentError`. Jobs that don't opt into notifications are unaffected.

**Steps are Continuable steps.** No parallel step concept. `progress.advance!` provides finer-grained tracking *inside* a step (e.g., across 10,000 rows); the current step name comes from Continuable.

### View helpers

```erb
<%= active_job_progress(execution) %>
<%= active_job_notifications(for: current_user) %>
```

Both are Turbo-stream-subscribed and update live without manual broadcast calls.

---

## 6. Database Schema

Two tables. One migration. Generated by the install generator.

### `active_job_executions`

```ruby
job_id:string:index:unique   # Active Job's job_id — join key with Continuable
job_class:string:index
status:string                # enqueued | running | completed | failed
current_step:string          # mirrored from Continuable
progress_current:integer
progress_total:integer       # nullable — indeterminate when nil
started_at:datetime
completed_at:datetime
error:text
timestamps
```

No `continuation_state` column. Continuable persists that itself; duplicating it would create a consistency problem with no good answer.

### `active_job_notifications`

```ruby
recipient_type:string        # polymorphic — usually "User"
recipient_id:string:index
job_id:string:index          # nullable — manual notifications may not tie to a job
event_type:string            # completed | failed | custom
title:string
description:text
metadata:jsonb               # arbitrary developer payload
actions:jsonb                # array of { label:, url:, method: } — optional
read_at:datetime             # null = unread
dismissed_at:datetime        # null = visible
timestamps
```

No append-only event log table in v1. Active Support instrumentation already provides an event stream; a persisted history can be added later if a real need emerges.

---

## 7. Hotwire Integration

Updates broadcast automatically when `active_job_executions` or `active_job_notifications` rows change. No manual `broadcast_*` calls in user code.

The progress helper renders indeterminate (no `total` declared) as a spinner; determinate as a progress bar with `current/total`. The notifications helper renders an inbox: unread items highlighted, "mark as read," "dismiss," "clear all," and any per-notification custom actions defined via the `actions:` argument.

---

## 8. Generators

Two generators, both intentionally small.

### Install (run once per app)

```bash
rails generate active_job:progress:install
```

Creates:

- migrations for both tables
- initializer with sensible defaults
- optional engine route mount (commented; user uncomments)
- shared view partials backing the two helpers in §5

### Scaffold (run per job class as needed)

```bash
rails generate active_job:progress:scaffold ImportJob
```

Produces a working, customizable example of embedded product UI for a specific job class:

- a controller (`ImportsController` by convention) with index and show actions scoped to executions of `ImportJob`
- views rendering `active_job_progress` for in-flight executions and `active_job_notifications` filtered to that job's events
- Turbo partials wired up so the developer can copy/restyle rather than reinvent the broadcast plumbing
- a routes snippet to paste into `config/routes.rb`

The generated code is meant to be **edited**. It is starter scaffolding, not a black box — the same posture as `rails generate scaffold`.

---

## 9. Lifecycle & Failure Behavior

The projection hooks via Active Support instrumentation around Active Job and Continuable. No monkey-patching of Continuable internals. If Continuable lacks an event the gem needs, the right fix is a PR upstream.

Cases the implementation must handle explicitly:

1. **No `tracks_progress`** — Continuable runs normally; no execution row, no notifications, no error.
2. **`tracks_progress` but no `progress.total` / `advance!`** — execution row exists, status transitions work, progress renders as indeterminate. Default for jobs whose work isn't naturally countable.
3. **Resume after crash** — Continuable resumes the job using its `job_id`. The gem looks up the existing execution row by `job_id` and continues updating it. **Does not create a new row on resume.**
4. **Job opted into notifications but enqueued without `recipient:`** — raises `ArgumentError` at enqueue time. Failing loudly and early is preferred over silently dropping notifications.
5. **Manual `notify(...)` after job completion** — allowed; written directly to the notifications table without going through lifecycle hooks.

---

## 10. Adapter Compatibility

Queue-adapter agnostic. Tested against:

- Solid Queue (first-class, prioritized)
- GoodJob
- Sidekiq (via Active Job)

---

## 11. Test Suite (Non-Negotiable)

### Coverage

- 95%+ on the core library
- Generator output booted and smoke-tested in CI
- Adapter matrix run on every PR

### Layers

**Unit** (Minitest first, Rails-native default; RSpec compatibility nice-to-have): macro behavior, progress arithmetic, projection updates, broadcast triggers, notification creation paths (declarative and manual), read/dismiss state transitions.

**Integration**: real job execution end-to-end — enqueue, run, advance, complete, notify; resume after simulated worker kill; Turbo stream delivery for both progress and notification UIs; generated views render correctly.

**Generator**: both generators produce code that boots, migrates, and passes a smoke test running a sample job and observing both its execution row and its resulting notification.

**Failure & recovery**: worker killed mid-step, resumed continuation reattaching to the existing execution row, concurrent updates to the same row.

> Notification idempotency on retry (deduping "failed" notifications across retries) is deferred to a future version. v1 may produce duplicate lifecycle notifications when a job is retried; this is documented behavior, not a bug.

### CI

GitHub Actions matrix across Ruby 3.3+, Rails 8.x, and the three queue adapters, on Postgres and SQLite where applicable. Red CI blocks merge.

---

## 12. API Stability

SemVer. The public API in §5 is the entire stable surface. Anything else is internal and may change.

Design rule: prefer adding less. Anything public should be designed as if it might be absorbed into Active Job core someday.

---

## 13. Stretch Goal

If `ActiveJob::Continuable` itself absorbs progress tracking, the eventual usage becomes:

```ruby
class ImportJob < ApplicationJob
  include ActiveJob::Continuable

  tracks_progress
  notify_on :completed, :failed

  step :import_rows do |step|
    progress.total(rows.count)
    rows.each { |r| import(r); progress.advance! }
  end
end
```

…with no separate `include`. Keeping this gem a thin projection over Continuable is what makes that future plausible. The notification inbox would likely remain a separate gem-level concern even in that future, since it isn't intrinsically about Active Job.

---

## 14. Success Criteria

A Rails developer can:

```bash
bundle add activejob-progress
rails generate active_job:progress:install
rails db:migrate
rails generate active_job:progress:scaffold ImportJob
```

…then add a few lines to an existing Continuable job and get:

- a durable, realtime progress UI embedded in their product
- a notification inbox for completed/failed jobs and any custom milestones they choose to record
- an admin status page at `/job_progress`
- resumable jobs that survive worker crashes

…without writing a custom status table, a custom notifications table, a custom channel, or a custom view.

---

## Inspirations

Active Storage. Action Mailbox. Solid Queue. Mission Control Jobs.

Not Temporal. Not Sidekiq Pro batches. Not workflow engines.
