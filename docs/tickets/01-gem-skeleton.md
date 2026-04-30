# 01 — Gem skeleton & engine bootstrap

## Goal
Stand up the gem as a Rails engine so subsequent tickets have a place to live.

## Scope
- `notificare.gemspec` declaring the gem, Ruby >= 3.3, Rails >= 8.1 dependency (Rails 8.1 ships `ActiveJob::Continuation`).
- `lib/active_job/notificare.rb` and `lib/active_job/notificare/engine.rb` — `Engine < ::Rails::Engine`, isolate namespace `ActiveJob::Notificare`.
- `lib/active_job/notificare/version.rb`.
- `Gemfile`, `Rakefile`, `bin/test`, dummy app under `test/dummy` generated via `rails new` (Rails 8, Solid Queue default).
- SimpleCov wired with a 95% threshold for `lib/`.
- Minitest + `ActiveSupport::TestCase` base under `test/test_helper.rb`.
- GitHub Actions workflow stub running `bin/test` on Ruby 3.3.

## Out of scope
Migrations, models, DSL, helpers — those land in later tickets.

## Acceptance criteria
- `bundle install && bin/test` exits 0 with the placeholder test suite.
- `bin/rails s` from `test/dummy` boots without error and the engine is mountable.
- SimpleCov report generated; threshold enforced.

## Tests (mandatory)
- `test/active_job/notificare/engine_test.rb` — asserts `ActiveJob::Notificare::Engine` is loaded, isolates namespace, and is mountable in the dummy app's routes.
- `test/active_job/notificare/version_test.rb` — version string matches SemVer.
