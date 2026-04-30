# 05 — Continuation integration, gem rename, & step DSL foundation

## Goal

Two coupled outcomes:

1. **Resume semantics (original ticket scope):** honor ERD §9 case 3 — resume after crash reuses the existing execution row, never creates a second row for the same `job_id`.
2. **Foundation for the inbox seam:** rename the gem to `notificare`, expose `include ActiveJob::Notificare` as the single seam (auto-includes `ActiveJob::Continuable`), and ship a `step(name, notify:)` DSL whose `notify:` value is captured on the job instance for the projection to read at `step_completed.active_job` time. The actual Notification row write lands in ticket 06; this ticket guarantees the wiring is in place.

## Scope

- Rename `koraci` → `notificare` (gemspec, top-level module, root require file).
- Rename `ActiveJob::Progress` → `ActiveJob::Notificare` across `lib/`, `app/`, generators, tests.
- `include ActiveJob::Notificare` auto-includes `ActiveJob::Continuable` and the new `StepDSL`.
- `tracks_progress` becomes opt-*out* (`tracks_progress false`); including the module is the opt-in.
- `lib/active_job/notificare/step_dsl.rb` — wraps Continuation's `step` with a `notify:` keyword. Stashes `notify:` per step name on the job instance (`@_notificare_step_notify`); exposes `notificare_step_notify_for(step_name)` for the projection.
- Projection (ticket 03) gains a fifth subscription: `step_completed.active_job`. Initially logs the would-write notification when `notify:` was declared. Row write deferred to ticket 06.
- Projection uses `Execution.find_or_create_by!(job_id: ...)` keyed solely on `job_id`. Idempotent across resumes.
- `current_step` is mirrored from Continuation's `step_started.active_job` event payload.
- On `perform_start.active_job`, if status is already `running` (resume path), do **not** reset `progress_current` or `started_at`; only update `current_step` and clear stale `error`.
- Document in code: "no `continuation_state` column — Continuation owns that" (ERD §6).
- Generator namespace: `active_job:notificare:install` / `:scaffold`. Engine mount default: `/notificare`.
- View helper names unchanged (`active_job_progress`, `active_job_notifications`) — public surface, not branded with the gem name. Stream names unchanged (`active_job_progress`, `active_job_notifications`) for the same reason.
- Table names unchanged (`active_job_executions`, `active_job_notifications`).

## Acceptance criteria

**Resume semantics (preserved from original scope):**
- Killing a worker mid-step and re-enqueueing via Continuation's resume path produces no duplicate `active_job_executions` row.
- `progress_current` continues from where it left off (Continuation's resume is responsible for replaying the step; `advance!` calls past the resume point increment the existing counter).
- `current_step` always reflects the most recent step.

**Rename & DSL foundation:**
- A job with `include ActiveJob::Notificare` boots, runs, and shows `ActiveJob::Continuable` in its ancestors.
- A step declared with `notify: :event_name` captures the symbol on the job instance; `job.notificare_step_notify_for(:step_name)` returns it. (Row write lives in ticket 06.)
- The projection subscribes to `step_completed.active_job` and the handler runs without errors when the event fires.
- `tracks_progress?` defaults to `true` after `include ActiveJob::Notificare`; `tracks_progress false` flips it off without removing the include.
- `bundle exec rake test` passes at ≥ 95% line coverage. `grep -rn "ActiveJob::Progress\|Koraci\|koraci" docs/ ERD.md CLAUDE.md` returns no hits except git-history references explicitly framed as "previously known as".

## Tests (mandatory)

- Integration: simulate a crash by raising mid-step, then re-perform with the same `job_id` — assert single row, status flow, `current_step` update.
- Integration: multi-step job advances `current_step` across step boundaries.
- Edge case: `find_or_create_by!` race — two simultaneous projections for the same `job_id` (uniqueness constraint catches the dup; one wins, the other recovers).
- Unit: `StepDslTest` — `step(name, notify:)` stashes the value; `step(name)` does not; `notificare_step_notify_for` returns nil for unstashed names.
- Unit: `step_completed.active_job` handler logs the would-write notification when `notify:` was declared, and is silent otherwise.
- Unit: `ConcernTest` — including the module sets `tracks_progress?` to true; `tracks_progress false` opts out; `ActiveJob::Continuable` is in `ancestors`.
