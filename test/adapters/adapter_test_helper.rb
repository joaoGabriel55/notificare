# Intentionally does NOT require simplecov — adapter tests run individually
# and would fail the 95% coverage gate. Coverage is enforced by `rake test`.

ENV["RAILS_ENV"] ||= "test"

require_relative "../../test/dummy/config/environment"
require "rails/test_help"
require "active_support/test_case"
require "active_job/test_helper"

# Run Notificare migrations (same path as the main test_helper).
ActiveRecord::Migrator.migrations_paths = [
  File.expand_path("../../test/dummy/db/migrate", __dir__)
]

module AdapterTestHelper
  # Create the Notificare tables plus any adapter-specific tables.
  def self.prepare_database!(extra_migration_paths: [])
    paths = ActiveRecord::Migrator.migrations_paths + Array(extra_migration_paths)
    ActiveRecord::MigrationContext.new(paths).migrate
  end

  # Shared assertions re-run for each adapter.
  module Assertions
    def assert_execution_completed(job_id)
      execution = ActiveJob::Notificare::Execution.find_by!(job_id: job_id)
      assert execution.completed?, "expected execution #{job_id} to be completed, got #{execution.status}"
      assert_not_nil execution.started_at
      assert_not_nil execution.completed_at
    end

    def assert_notification_written(recipient:, event_type: nil)
      scope = ActiveJob::Notificare::Notification.where(recipient: recipient)
      scope = scope.where(event_type: event_type) if event_type
      assert scope.exists?, "expected a #{event_type || 'any'} notification for #{recipient.inspect}"
    end
  end

  # Base class every adapter integration test inherits from.
  class TestCase < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    include Assertions

    setup do
      ActiveJob::Notificare::Projection.unsubscribe!
      ActiveJob::Notificare::Projection.subscribe!
      @user = User.create!(name: "Adapter Test User")
    end

    teardown do
      ActiveJob::Notificare::Projection.unsubscribe!
      ActiveJob::Notificare::Notification.delete_all
      ActiveJob::Notificare::Execution.delete_all
      User.delete_all
    end
  end
end
