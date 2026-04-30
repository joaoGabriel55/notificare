require "test_helper"

class ActiveJob::Notificare::NotifyOnTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
    @user = User.create!(name: "Test User")
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  # --- unit: notify_on DSL ---

  test "notify_on registers the event list on the job class" do
    job_class = Class.new(ApplicationJob) do
      include ActiveJob::Notificare
      notify_on :completed, :failed
    end
    assert_equal %i[completed failed], job_class.notificare_notify_on
  end

  test "notificare_notify_on defaults to empty array without notify_on call" do
    job_class = Class.new(ApplicationJob) { include ActiveJob::Notificare }
    assert_equal [], job_class.notificare_notify_on
  end

  test "notify_on is independent per class" do
    parent = Class.new(ApplicationJob) do
      include ActiveJob::Notificare
      notify_on :completed
    end
    child = Class.new(parent) { notify_on :failed }
    assert_equal %i[completed], parent.notificare_notify_on
    assert_equal %i[failed], child.notificare_notify_on
  end

  # --- unit: step notify: symbol form ---

  test "step_completed with notify: :sym writes custom notification row" do
    job = StepDslTestJob.new
    job.recipient = @user
    job.send(:step, :validate, notify: :validated) { :ok }

    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      step = Struct.new(:name).new(:validate)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end

    notification = ActiveJob::Notificare::Notification.first
    assert notification.custom?
    assert_equal "StepDslTestJob: validated", notification.title
    assert_equal({ "event" => "validated" }, notification.metadata)
    assert_equal job.job_id, notification.job_id
    assert_equal @user, notification.recipient
  end

  test "step_completed with notify: hash form overwrites title, description, and merges metadata" do
    job = StepDslTestJob.new
    job.recipient = @user
    job.send(:step, :process, notify: { event: :processed, title: "Processing complete", description: "rows done", metadata: { count: 42 } }) { :ok }

    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      step = Struct.new(:name).new(:process)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end

    notification = ActiveJob::Notificare::Notification.first
    assert notification.custom?
    assert_equal "Processing complete", notification.title
    assert_equal "rows done", notification.description
    assert_equal({ "event" => "processed", "count" => 42 }, notification.metadata)
  end

  test "step_completed with notify: hash form uses default title when title not provided" do
    job = StepDslTestJob.new
    job.recipient = @user
    job.send(:step, :validate, notify: { event: :validated }) { :ok }

    step = Struct.new(:name).new(:validate)
    ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)

    notification = ActiveJob::Notificare::Notification.first
    assert_equal "StepDslTestJob: validated", notification.title
  end

  # --- negative: no recipient skips write ---

  test "step_completed with notify: but no recipient does not write a row" do
    job = StepDslTestJob.new
    job.send(:step, :validate, notify: :validated) { :ok }

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      step = Struct.new(:name).new(:validate)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end
  end

  test "step_completed without notify: does not write a row" do
    job = StepDslTestJob.new
    job.recipient = @user
    job.send(:step, :bare) { :ok }

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      step = Struct.new(:name).new(:bare)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end
  end

  # --- integration: lifecycle notifications ---

  test "notify_on :completed produces one notification on successful job run" do
    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      NotifyOnTestJob.perform_later(recipient: @user)
      perform_enqueued_jobs
    end

    notification = ActiveJob::Notificare::Notification.first
    assert notification.completed?
    assert_equal "NotifyOnTestJob completed", notification.title
    assert_equal @user, notification.recipient
    assert_not_nil notification.job_id
  end

  test "notify_on :failed produces one notification with exception message on failure" do
    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      FailingNotifyOnTestJob.perform_later(recipient: @user)
      assert_raises(StandardError) { perform_enqueued_jobs }
    end

    notification = ActiveJob::Notificare::Notification.first
    assert notification.failed?
    assert_equal "FailingNotifyOnTestJob failed", notification.title
    assert_equal "notify_on failure", notification.description
    assert_equal @user, notification.recipient
  end

  test "notify_on :completed does not fire for failed job" do
    FailingNotifyOnTestJob.perform_later(recipient: @user)
    assert_raises(StandardError) { perform_enqueued_jobs }

    notifications = ActiveJob::Notificare::Notification.all
    assert_equal 1, notifications.count
    assert_equal "failed", notifications.first.event_type
  end

  test "notify_on :failed does not fire for successful job" do
    NotifyOnTestJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    notifications = ActiveJob::Notificare::Notification.all
    assert_equal 1, notifications.count
    assert_equal "completed", notifications.first.event_type
  end

  # --- integration: multi-step with notify: ---

  test "multi-step job with notify: on two of three steps produces exactly two custom notifications" do
    assert_difference -> { ActiveJob::Notificare::Notification.count }, +2 do
      StepNotifyTestJob.perform_later(recipient: @user)
      perform_enqueued_jobs
    end

    notifications = ActiveJob::Notificare::Notification.all.to_a
    event_names = notifications.map { |n| n.metadata&.dig("event") }.sort
    assert_equal %w[processed validated], event_names
  end

  test "step with hash notify: stores correct title, description, and metadata" do
    StepNotifyTestJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    processed = ActiveJob::Notificare::Notification.all.find { |n| n.metadata&.dig("event") == "processed" }
    assert_not_nil processed
    assert_equal "Processing complete", processed.title
    assert_equal "rows done", processed.description
    assert_equal({ "event" => "processed", "count" => 42 }, processed.metadata)
  end

  # --- negative: step that raises produces zero step-level notifications ---

  test "a step that raises produces zero step-level notification rows" do
    FailingStepNotifyTestJob.perform_later(recipient: @user)
    # Continuation retries instead of raising when a step errors after making progress,
    # so perform_enqueued_jobs does not raise here.
    perform_enqueued_jobs

    # ok_step completed → one notification; boom_step raised → no notification written.
    notifications = ActiveJob::Notificare::Notification.all.to_a
    assert_equal 1, notifications.count
    assert_equal "ok_done", notifications.first.metadata["event"]
  end

  # --- negative: job without notify_on produces zero notifications ---

  test "job without notify_on and without step notify: produces zero notifications on completion" do
    TrackedTestJob.perform_later
    perform_enqueued_jobs
    assert_equal 0, ActiveJob::Notificare::Notification.count
  end

  test "job without notify_on and without step notify: produces zero notifications on failure" do
    FailingTrackedTestJob.perform_later
    assert_raises(StandardError) { perform_enqueued_jobs }
    assert_equal 0, ActiveJob::Notificare::Notification.count
  end
end
