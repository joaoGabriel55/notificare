# 11 — Scaffold generator (Surface 2)

## Goal
ERD §8: `rails generate active_job:progress:scaffold ImportJob` produces editable starter UI for embedded product pages.

## Scope
- `lib/generators/active_job/progress/scaffold/scaffold_generator.rb`.
- Inputs: a job class name. Generator validates that the class includes `ActiveJob::Progress`.
- Output (for `ImportJob` example):
  - `app/controllers/imports_controller.rb` with `index` (executions for `ImportJob`, scoped to `current_recipient`) and `show`.
  - `app/views/imports/index.html.erb` and `show.html.erb` using the helpers from ticket 09 plus filtered notifications (`for: current_recipient`, scoped by `job_class`).
  - Turbo partials demonstrating broadcast subscriptions — copy-pasteable, not a black box.
  - A routes snippet printed to stdout (never auto-mutates `config/routes.rb` — the developer pastes it). ERD §8 phrasing.
- Naming convention: `ImportJob` → `ImportsController`, `imports/` views, `imports_path`. Allow override flags `--controller=`, `--prefix=`.

## Acceptance criteria
- Running the generator for a valid job class creates exactly the listed files.
- Running against a class missing the concern aborts with a clear error.
- Generated code boots in the dummy app, and a smoke test running a sample job shows progress + notifications in the generated views.

## Tests (mandatory)
- Generator test asserting file contents.
- Boot-and-smoke test in CI: generate scaffold, run sample job inline, request generated index/show, assert HTML includes progress + notification markup.
- Override flag tests for `--controller=` and `--prefix=`.
