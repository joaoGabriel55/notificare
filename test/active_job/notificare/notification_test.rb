require "test_helper"

class ActiveJob::Notificare::NotificationTest < ActiveSupport::TestCase
  def build_notification(overrides = {})
    user = User.create!(name: "Test User")
    ActiveJob::Notificare::Notification.new(
      {
        recipient: user,
        event_type: "completed",
        title: "ImportJob completed"
      }.merge(overrides)
    )
  end

  # --- enum ---

  test "event_type enum covers completed, failed, custom" do
    assert_equal({ "completed" => "completed", "failed" => "failed", "custom" => "custom" },
                 ActiveJob::Notificare::Notification.event_types)
  end

  test "completed? predicate works" do
    n = build_notification(event_type: "completed")
    assert n.completed?
    assert_not n.failed?
    assert_not n.custom?
  end

  test "failed? predicate works" do
    n = build_notification(event_type: "failed")
    assert n.failed?
  end

  test "custom? predicate works" do
    n = build_notification(event_type: "custom", metadata: { "event" => "validated" })
    assert n.custom?
  end

  # --- scopes ---

  test "default scope orders by created_at desc" do
    user = User.create!(name: "User")
    first = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "First")
    second = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "failed", title: "Second")
    assert_equal second, ActiveJob::Notificare::Notification.first
    assert_equal first, ActiveJob::Notificare::Notification.last
  end

  test "unread scope excludes read notifications" do
    user = User.create!(name: "User")
    unread = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Unread")
    read = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Read", read_at: Time.current)
    assert_includes ActiveJob::Notificare::Notification.unread, unread
    assert_not_includes ActiveJob::Notificare::Notification.unread, read
  end

  test "visible scope excludes dismissed notifications" do
    user = User.create!(name: "User")
    visible = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Visible")
    dismissed = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Dismissed", dismissed_at: Time.current)
    assert_includes ActiveJob::Notificare::Notification.visible, visible
    assert_not_includes ActiveJob::Notificare::Notification.visible, dismissed
  end

  # --- read? / dismissed? ---

  test "read? returns false when read_at is nil" do
    n = build_notification
    assert_not n.read?
  end

  test "read? returns true when read_at is set" do
    n = build_notification(read_at: Time.current)
    assert n.read?
  end

  test "dismissed? returns false when dismissed_at is nil" do
    n = build_notification
    assert_not n.dismissed?
  end

  test "dismissed? returns true when dismissed_at is set" do
    n = build_notification(dismissed_at: Time.current)
    assert n.dismissed?
  end

  # --- mark_read! / dismiss! ---

  test "mark_read! sets read_at and persists" do
    user = User.create!(name: "User")
    n = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Title")
    assert_not n.read?
    n.mark_read!
    assert n.read?
    assert_not_nil n.reload.read_at
  end

  test "mark_read! is idempotent" do
    user = User.create!(name: "User")
    n = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Title")
    n.mark_read!
    original_read_at = n.read_at
    n.mark_read!
    assert_in_delta original_read_at.to_f, n.read_at.to_f, 0.001
  end

  test "dismiss! sets dismissed_at and persists" do
    user = User.create!(name: "User")
    n = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Title")
    assert_not n.dismissed?
    n.dismiss!
    assert n.dismissed?
    assert_not_nil n.reload.dismissed_at
  end

  test "dismiss! is idempotent" do
    user = User.create!(name: "User")
    n = ActiveJob::Notificare::Notification.create!(recipient: user, event_type: "completed", title: "Title")
    n.dismiss!
    original_dismissed_at = n.dismissed_at
    n.dismiss!
    assert_in_delta original_dismissed_at.to_f, n.dismissed_at.to_f, 0.001
  end

  # --- metadata JSON round-trip ---

  test "metadata is round-tripped as JSON" do
    user = User.create!(name: "User")
    n = ActiveJob::Notificare::Notification.create!(
      recipient: user,
      event_type: "custom",
      title: "Custom",
      metadata: { "event" => "validated", "count" => 5 }
    )
    reloaded = ActiveJob::Notificare::Notification.find(n.id)
    assert_equal({ "event" => "validated", "count" => 5 }, reloaded.metadata)
  end
end
