require "simplecov"

SimpleCov.start do
  add_filter "/test/"
  add_filter "/test/dummy/"
  track_files "lib/**/*.rb"
  minimum_coverage 95
end

ENV["RAILS_ENV"] ||= "test"

require_relative "../test/dummy/config/environment"

require "rails/test_help"
require "active_support/test_case"

ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]

ActiveRecord::MigrationContext.new(
  ActiveRecord::Migrator.migrations_paths
).migrate
