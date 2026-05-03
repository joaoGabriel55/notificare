require_relative "adapter_test_helper"
require "sidekiq/test_api"

# Notificare tables are created in AdapterTestHelper.prepare_database!
# Sidekiq stores jobs in Redis — no extra DB tables are needed.
AdapterTestHelper.prepare_database!

# Use Sidekiq fake mode so perform_later buffers jobs without executing them.
# We drain explicitly after each perform_later so the enqueue.active_job event
# fires (and creates the Execution row) before the job body runs — the same
# event-ordering fix documented for Rails' own :test adapter.
Sidekiq.testing!(:fake)

class SidekiqAdapterTest < AdapterTestHelper::TestCase
  setup do
    ActiveJob::Base.queue_adapter = :sidekiq
  end

  teardown do
    ActiveJob::Base.queue_adapter = :test
    Sidekiq::Job.clear_all
  end

  # Drain all Sidekiq-buffered jobs by executing them via the standard
  # Sidekiq::ActiveJob::Wrapper path (fires all AS::Notifications events).
  def drain_sidekiq
    Sidekiq::Job.drain_all
  rescue StandardError
    # drain_all re-raises job failures. The perform.active_job event already
    # fired with exception_object, so the Notificare row is already failed.
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  test "enqueues job and creates execution row with enqueued status" do
    job = NotifyOnTestJob.perform_later(recipient: @user)

    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.enqueued?, "expected enqueued status after perform_later"
  end

  test "draining transitions execution to completed" do
    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_sidekiq
    assert_execution_completed(job.job_id)
  end

  test "completed notification is written after drain" do
    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_sidekiq
    assert_notification_written(recipient: @user, event_type: "completed")
  end

  test "failed job transitions to failed status" do
    job = FailingTrackedTestJob.perform_later
    drain_sidekiq
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.failed?, "expected failed status"
    assert_equal "something went wrong", execution.error
  end

  test "step-level notifications are written for each completed step" do
    job = StepNotifyTestJob.perform_later(recipient: @user)
    drain_sidekiq
    notifications = ActiveJob::Notificare::Notification.where(recipient: @user, event_type: "custom")
    assert notifications.exists?, "expected at least one custom (step) notification"
  end

  # ---------------------------------------------------------------------------
  # Smoke: AS::Notifications instrumentation fires identically to :test adapter
  # ---------------------------------------------------------------------------

  test "AS::Notifications events fire for Sidekiq identically to the test adapter" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/\.active_job$/) do |name, *|
      events << name
    end

    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_sidekiq

    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_includes events, "enqueue.active_job"
    assert_includes events, "perform_start.active_job"
    assert_includes events, "perform.active_job"
  end
end
