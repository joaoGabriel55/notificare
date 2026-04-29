# 05 — Continuable integration & resume semantics

## Goal
Honor ERD §9 case 3: resume after crash reuses the existing execution row, never creates a second row for the same `job_id`.

## Scope
- Projection (ticket 03) uses `Execution.find_or_create_by!(job_id: ...)` keyed solely on `job_id`. Idempotent across resumes.
- `current_step` is mirrored from Continuable's step events — read step name from event payload, persist on the execution row.
- On `perform_start`, if status is already `running` (resume path), do **not** reset `progress_current` or `started_at`; only update `current_step` and clear stale `error`.
- Document explicitly in code: "no `continuation_state` column — Continuable owns that" (ERD §6).

## Acceptance criteria
- Killing a worker mid-step and re-enqueueing via Continuable's resume path produces no duplicate `active_job_executions` row.
- `progress_current` continues from where it left off (Continuable's resume is responsible for replaying the step; `advance!` calls past the resume point increment the existing counter).
- `current_step` always reflects the most recent step.

## Tests (mandatory)
- Integration: simulate a crash by raising mid-step, then re-perform with the same `job_id` — assert single row, status flow, `current_step` update.
- Integration: multi-step job advances `current_step` across step boundaries.
- Edge case: `find_or_create_by!` race — two simultaneous projections for the same `job_id` (uniqueness constraint catches the dup; one wins, the other recovers).
