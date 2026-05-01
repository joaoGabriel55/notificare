require "test_helper"

class ActiveJob::Notificare::IntegrationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(name: "Integration User")
    user = @user
    ActiveJob::Notificare.current_recipient_proc = -> { user }
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
  end

  teardown do
    ActiveJob::Notificare.current_recipient_proc = nil
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Notification.delete_all
    ActiveJob::Notificare::Execution.delete_all
    User.delete_all
  end

  test "progress helper renders execution with determinate progress after job runs" do
    ProgressDslTestJob.perform_later
    perform_enqueued_jobs

    execution = ActiveJob::Notificare::Execution.last
    assert execution, "expected an execution row to exist"

    get home_url(user_id: @user.id, job_id: execution.job_id)
    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select "progress"
  end

  test "notifications helper renders notification inbox after job completes" do
    NotifyOnTestJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    get home_url(user_id: @user.id)
    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select ".notificare-inbox"
    assert_select ".notificare-notification"
    assert_select "button", text: "Mark as read"
    assert_select "button", text: "Dismiss"
    assert_select "button", text: "Clear all"
  end

  test "notifications inbox does not show dismissed notifications on subsequent request" do
    NotifyOnTestJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    notification = ActiveJob::Notificare::Notification.where(recipient: @user).first
    notification.dismiss!

    get home_url(user_id: @user.id)
    assert_response :success
    assert_select ".notificare-notification", count: 0
  end
end
