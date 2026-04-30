require "test_helper"

class ActiveJob::Notificare::ManualNotifyTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
    @user = User.create!(name: "Notify User")
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  # --- unit: notify writes expected row ---

  test "notify writes a custom notification row with all fields" do
    job = ManualNotifyTestJob.new
    job.recipient = @user

    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      job.notify(
        title: "halfway done",
        description: "midpoint reached",
        metadata: { step: 1 },
        actions: [ "view", "dismiss" ]
      )
    end

    notification = ActiveJob::Notificare::Notification.first
    assert notification.custom?
    assert_equal "halfway done", notification.title
    assert_equal "midpoint reached", notification.description
    assert_equal({ "step" => 1 }, notification.metadata)
    assert_equal [ "view", "dismiss" ], notification.actions
    assert_equal @user, notification.recipient
    assert_equal job.job_id, notification.job_id
  end

  test "notify without a recipient skips the write silently" do
    job = ManualNotifyTestJob.new

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      job.notify(title: "no recipient")
    end
  end

  test "notify flips uses_notify? to true on the job class" do
    klass = Class.new(ApplicationJob) do
      include ActiveJob::Notificare
      def perform; end
    end

    job = klass.new
    job.recipient = @user
    refute klass.uses_notify?

    job.notify(title: "first call")
    assert klass.uses_notify?
  end

  # --- unit: enqueue-time recipient enforcement ---

  test "job with notify_on raises ArgumentError when enqueued without recipient:" do
    error = assert_raises(ArgumentError) { ManualNotifyTestJob.perform_later }
    assert_match(/ManualNotifyTestJob requires a `recipient:` keyword argument/, error.message)
  end

  test "job with uses_notify! raises ArgumentError when enqueued without recipient:" do
    error = assert_raises(ArgumentError) { UsesNotifyTestJob.perform_later }
    assert_match(/UsesNotifyTestJob requires a `recipient:` keyword argument/, error.message)
  end

  test "job with notify_on is enqueued successfully when recipient: is supplied" do
    assert_nothing_raised do
      ManualNotifyTestJob.perform_later(recipient: @user)
    end
  end

  test "job without notify_on or uses_notify! is unaffected by recipient enforcement" do
    assert_nothing_raised do
      TrackedTestJob.perform_later
    end
  end

  test "UntrackedTestJob is unaffected by recipient enforcement" do
    assert_nothing_raised do
      UntrackedTestJob.perform_later
    end
  end

  # --- unit: uses_notify! DSL ---

  test "uses_notify! marks the class as requiring a recipient at enqueue time" do
    assert UsesNotifyTestJob.uses_notify?
  end

  test "uses_notify? defaults to false for a plain included job" do
    klass = Class.new(ApplicationJob) { include ActiveJob::Notificare }
    refute klass.uses_notify?
  end

  # --- integration: actions round-trip ---

  test "actions array round-trips through the JSON column" do
    ManualNotifyTestJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    custom_notifications = ActiveJob::Notificare::Notification.where(event_type: "custom")
    assert_equal 1, custom_notifications.count
    assert_equal [ "view", "dismiss" ], custom_notifications.first.actions
  end

  # --- integration: post-completion notify persists ---

  test "notify called outside of the job lifecycle still persists a row" do
    job = ManualNotifyTestJob.new
    job.recipient = @user

    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      job.notify(title: "post-completion notice", description: "written after perform")
    end

    notification = ActiveJob::Notificare::Notification.first
    assert notification.custom?
    assert_equal "post-completion notice", notification.title
    assert_equal "written after perform", notification.description
    assert_equal @user, notification.recipient
    assert_equal job.job_id, notification.job_id
  end

  test "notify called inside perform writes row with correct job_id" do
    ManualNotifyTestJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    custom = ActiveJob::Notificare::Notification.find_by(event_type: "custom")
    assert_not_nil custom
    assert_not_nil custom.job_id
    assert_equal @user, custom.recipient
  end
end
