require "test_helper"

class ActiveJob::Notificare::NotificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Alice")
    @other_user = User.create!(name: "Bob")

    @notification = ActiveJob::Notificare::Notification.create!(
      recipient: @user,
      event_type: "completed",
      title: "Alice's job"
    )
    @other_notification = ActiveJob::Notificare::Notification.create!(
      recipient: @other_user,
      event_type: "completed",
      title: "Bob's job"
    )

    user = @user
    ActiveJob::Notificare.current_recipient_proc = -> { user }
  end

  teardown do
    ActiveJob::Notificare.current_recipient_proc = nil
    ActiveJob::Notificare::Notification.delete_all
    User.delete_all
  end

  test "PATCH read marks notification as read" do
    patch notificare.read_notification_path(@notification)
    assert_response :ok
    assert @notification.reload.read?
  end

  test "PATCH read returns 404 for another recipient's notification" do
    patch notificare.read_notification_path(@other_notification)
    assert_response :not_found
    assert_not @other_notification.reload.read?
  end

  test "PATCH dismiss marks notification as dismissed" do
    patch notificare.dismiss_notification_path(@notification)
    assert_response :ok
    assert @notification.reload.dismissed?
  end

  test "PATCH dismiss returns 404 for another recipient's notification" do
    patch notificare.dismiss_notification_path(@other_notification)
    assert_response :not_found
    assert_not @other_notification.reload.dismissed?
  end

  test "DELETE clear destroys all visible notifications for current recipient" do
    visible = ActiveJob::Notificare::Notification.create!(
      recipient: @user, event_type: "failed", title: "Another notification"
    )

    delete notificare.clear_notifications_path
    assert_response :ok

    assert_not ActiveJob::Notificare::Notification.exists?(@notification.id)
    assert_not ActiveJob::Notificare::Notification.exists?(visible.id)
    assert ActiveJob::Notificare::Notification.exists?(@other_notification.id)
  end

  test "DELETE clear does not destroy already dismissed notifications" do
    @notification.dismiss!

    delete notificare.clear_notifications_path
    assert_response :ok

    assert ActiveJob::Notificare::Notification.exists?(@notification.id)
  end

  test "returns 401 when current recipient cannot be resolved" do
    ActiveJob::Notificare.current_recipient_proc = -> { nil }

    patch notificare.read_notification_path(@notification)
    assert_response :unauthorized
  end
end
