# 02 — Install generator & schema

## Goal
Single command brings up both tables, an initializer, the route stub, and the shared partials.

## Scope
- `lib/generators/active_job/progress/install/install_generator.rb` (Rails generator).
- One timestamped migration creating both tables exactly as defined in ERD §6:
  - `active_job_executions` — `job_id` (string, unique index), `job_class` (string, indexed), `status`, `current_step`, `progress_current` (int), `progress_total` (int, nullable), `started_at`, `completed_at`, `error` (text), timestamps.
  - `active_job_notifications` — `recipient_type`, `recipient_id` (indexed), `job_id` (indexed, nullable), `event_type`, `title`, `description`, `metadata` (jsonb / json fallback for SQLite), `actions` (jsonb), `read_at`, `dismissed_at`, timestamps.
- Initializer `config/initializers/active_job_progress.rb` with documented defaults.
- Commented `mount ActiveJob::Progress::Engine => "/job_progress"` appended to `config/routes.rb`.
- Shared view partials seeded under `app/views/active_job/progress/` (empty stubs; ticket 09 fills them).
- `metadata`/`actions` columns must use `jsonb` on Postgres, `json` on MySQL, fall back to `text` with JSON serialization on SQLite. Generator detects the adapter.

## Acceptance criteria
- `rails generate active_job:progress:install` produces the migration, initializer, route stub, and partial files.
- `rails db:migrate` succeeds on Postgres and SQLite in the dummy app.
- Idempotent — running twice does not duplicate the migration (timestamp + name guard).

## Tests (mandatory)
- Generator test (`Rails::Generators::TestCase`) asserting all files are created with expected contents on Postgres and SQLite.
- Schema test booting the dummy app post-migration and verifying both tables exist with the documented columns and indexes (`ActiveRecord::Base.connection.columns` / `.indexes`).
- Re-run safety test: invoking the generator twice fails cleanly without overwriting.
