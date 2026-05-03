source "https://rubygems.org"

gemspec

gem "rails", ">= 8.0"
gem "sqlite3"
gem "turbo-rails"
gem "importmap-rails"
gem "simplecov", require: false
gem "minitest"
gem "minitest-reporters", require: false
gem "rubocop-rails-omakase", require: false

# Adapter matrix — engines must be loaded at boot so their app/models paths
# are registered with Rails' autoloader before initialization completes.
gem "solid_queue"
gem "good_job"
gem "sidekiq"
gem "pg", require: false   # only needed when DATABASE_URL points to Postgres
gem "csv"                  # no longer a default gem in Ruby 3.4
