require_relative "adapter_test_helper"

# Load SolidQueue tables into the test database using the schema shipped with
# the dummy app (queue_schema.rb). force: :cascade makes this idempotent.
load File.expand_path("../../test/dummy/db/queue_schema.rb", __dir__)

# Notificare tables are created in AdapterTestHelper.prepare_database!
AdapterTestHelper.prepare_database!

class SolidQueueAdapterTest < AdapterTestHelper::TestCase
  setup do
    ActiveJob::Base.queue_adapter = :solid_queue
  end

  teardown do
    ActiveJob::Base.queue_adapter = :test
    SolidQueue::Job.delete_all
  end

  # ---------------------------------------------------------------------------
  # Drain helper
  # Execute all SolidQueue::ReadyExecution rows using the same code path that
  # SolidQueue::ClaimedExecution#execute uses internally.
  # ---------------------------------------------------------------------------
  def drain_solid_queue
    SolidQueue::ReadyExecution.includes(:job).each do |ready_exec|
      job_args = ready_exec.job.arguments.merge("provider_job_id" => ready_exec.job.id)
      ActiveJob::Base.execute(job_args)
      ready_exec.job.finished!
      ready_exec.destroy!
    rescue StandardError
      # perform.active_job already fired with exception_object, so the
      # Notificare execution row is already updated to failed.
    end
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
    drain_solid_queue
    assert_execution_completed(job.job_id)
  end

  test "completed notification is written after drain" do
    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_solid_queue
    assert_notification_written(recipient: @user, event_type: "completed")
  end

  test "failed job transitions to failed status" do
    job = FailingTrackedTestJob.perform_later
    drain_solid_queue
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.failed?, "expected failed status"
    assert_equal "something went wrong", execution.error
  end

  test "step-level notifications are written for each completed step" do
    job = StepNotifyTestJob.perform_later(recipient: @user)
    drain_solid_queue
    notifications = ActiveJob::Notificare::Notification.where(recipient: @user, event_type: "custom")
    assert notifications.exists?, "expected at least one custom (step) notification"
  end

  # ---------------------------------------------------------------------------
  # Smoke: AS::Notifications instrumentation fires identically to :test adapter
  # ---------------------------------------------------------------------------

  test "AS::Notifications events fire for SolidQueue identically to the test adapter" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/\.active_job$/) do |name, *|
      events << name
    end

    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_solid_queue

    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_includes events, "enqueue.active_job"
    assert_includes events, "perform_start.active_job"
    assert_includes events, "perform.active_job"
  end
end
