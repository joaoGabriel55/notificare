# 12 — Adapter matrix & CI

## Goal
ERD §10 + §11: prove the gem works against Solid Queue, GoodJob, and Sidekiq, on Postgres and SQLite where applicable.

## Scope
- Test harness selecting the queue adapter and database via `QUEUE_ADAPTER` / `DATABASE_URL` env vars.
- Three adapter test files re-running the integration suite:
  - `test/adapters/solid_queue_test.rb` (Postgres only)
  - `test/adapters/good_job_test.rb` (Postgres only)
  - `test/adapters/sidekiq_test.rb` (Redis service)
- GitHub Actions matrix: `{ ruby: [3.3, 3.4], adapter: [solid_queue, good_job, sidekiq], db: [postgres, sqlite] }` with valid combinations (sqlite only for inline tests where applicable).
- Service containers: Postgres, Redis. Caching for bundler.

## Acceptance criteria
- All matrix legs green on a fresh PR.
- A regression in any adapter blocks merge.

## Tests (mandatory)
- The adapter integration tests above must each:
  - Enqueue a tracked job.
  - Drain the queue using the adapter's documented test pattern.
  - Assert execution row transitions and at least one notification written.
- Smoke test confirming AS::Notifications instrumentation fires identically across adapters (no adapter-specific projection branching allowed in `lib/`).
