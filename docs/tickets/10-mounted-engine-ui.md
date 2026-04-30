# 10 — Mounted engine UI (Surface 1)

## Goal
Admin-flavored status page at `/notificare` per ERD §4.

## Scope
- Controllers under `ActiveJob::Notificare::Engine`:
  - `ExecutionsController#index` — paginated list of recent executions, filter by status and job class.
  - `ExecutionsController#show` — single execution detail with live progress + recent notifications tied to that `job_id`.
- Views styled with minimal CSS (no Tailwind requirement; ship a small stylesheet, follow Mission Control's convention of being reasonable out of the box).
- Engine-level routes wired in `config/routes.rb` of the engine.
- Authentication: ship an initializer hook `config.authenticate_with = -> { ... }` that the host app overrides; default refuses access in production unless configured (fail safe).

## Acceptance criteria
- Mounting the engine and visiting `/notificare` renders the index.
- Live progress updates without a page refresh on an in-flight execution's show page.
- Without the auth proc configured, production environments deny access.

## Tests (mandatory)
- Engine routing tests for index/show.
- Controller tests for filters, pagination, and 200 responses.
- Auth test: production env without configured proc → 403; with proc returning false → 403; with proc returning true → 200.
- System test (Capybara + Turbo) on the dummy app: run a job, watch the show page update progress live.
