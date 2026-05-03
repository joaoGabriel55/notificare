require "test_helper"

class ActiveJob::Notificare::ViewHelpersTest < ActionView::TestCase
  include ActiveJob::Notificare::ViewHelpers
  helper ActiveJob::Notificare::Engine.routes.url_helpers

  test "active_job_notificare renders progress element in determinate mode" do
    execution = ActiveJob::Notificare::Execution.new(
      job_id: "det-job-123",
      job_class: "TestJob",
      status: "running",
      progress_current: 3,
      progress_total: 10,
      current_step: "processing"
    )

    html = active_job_notificare(execution)

    assert_match(/notificare-progress/, html)
    assert_match(/notificare-progress__bar/, html)
    assert_match(/notificare-progress__label/, html)
    assert_match(/notificare-progress__step/, html)
    assert_match(/<progress/, html)
    assert_match(/value="3"/, html)
    assert_match(/max="10"/, html)
    assert_match(/30%/, html)
    assert_match(/processing/, html)
    assert_match(/turbo-cable-stream-source/, html)
  end

  test "active_job_notificare renders spinner in indeterminate mode" do
    execution = ActiveJob::Notificare::Execution.new(
      job_id: "indet-job-456",
      job_class: "TestJob",
      status: "running",
      progress_current: 0,
      progress_total: nil,
      current_step: "validating"
    )

    html = active_job_notificare(execution)

    assert_no_match(/<progress/, html)
    assert_match(/notificare-progress__spinner/, html)
    assert_match(/validating/, html)
    assert_match(/turbo-cable-stream-source/, html)
  end

  test "active_job_notificare renders without current_step" do
    execution = ActiveJob::Notificare::Execution.new(
      job_id: "no-step-job",
      job_class: "TestJob",
      status: "running",
      progress_current: 0,
      progress_total: nil,
      current_step: nil
    )

    html = active_job_notificare(execution)

    assert_match(/notificare-progress__spinner/, html)
    assert_no_match(/notificare-progress__step/, html)
  end

  test "active_job_notifications renders inbox with visible notifications" do
    user = User.create!(name: "Inbox User")
    notification = ActiveJob::Notificare::Notification.create!(
      recipient: user,
      event_type: "completed",
      title: "Job completed",
      description: "Your job finished successfully"
    )

    html = active_job_notifications(for: user)

    assert_match(/notificare-inbox/, html)
    assert_match(/notificare-notification/, html)
    assert_match(/notificare-notification__title/, html)
    assert_match(/notificare-notification__description/, html)
    assert_match(/notificare-notification__actions/, html)
    assert_match(/Job completed/, html)
    assert_match(/Your job finished successfully/, html)
    assert_match(/Mark as read/, html)
    assert_match(/Dismiss/, html)
    assert_match(/Clear all/, html)
    assert_match(/turbo-cable-stream-source/, html)

    notification.destroy
    user.destroy
  end

  test "active_job_notifications marks unread notifications with unread class" do
    user = User.create!(name: "Unread User")
    unread = ActiveJob::Notificare::Notification.create!(
      recipient: user, event_type: "completed", title: "Unread notification"
    )
    read = ActiveJob::Notificare::Notification.create!(
      recipient: user, event_type: "failed", title: "Read notification"
    )
    read.mark_read!

    html = active_job_notifications(for: user)

    assert_match(/notificare-notification--unread/, html)
    assert_match(/class="notificare-notification notificare-notification--unread"/, html)
    assert_match(/class="notificare-notification"/, html)
    assert_no_match(/Mark as read.*Mark as read/m, html)

    [ unread, read, user ].each(&:destroy)
  end

  test "active_job_notifications does not render dismissed notifications" do
    user = User.create!(name: "Dismiss User")
    visible = ActiveJob::Notificare::Notification.create!(
      recipient: user, event_type: "completed", title: "Visible notification"
    )
    dismissed = ActiveJob::Notificare::Notification.create!(
      recipient: user, event_type: "failed", title: "Dismissed notification"
    )
    dismissed.dismiss!

    html = active_job_notifications(for: user)

    assert_match(/Visible notification/, html)
    assert_no_match(/Dismissed notification/, html)

    [ visible, dismissed, user ].each(&:destroy)
  end

  test "active_job_notifications renders per-notification action links" do
    user = User.create!(name: "Actions User")
    notification = ActiveJob::Notificare::Notification.create!(
      recipient: user,
      event_type: "completed",
      title: "Job done",
      actions: [ { "label" => "View report", "url" => "/reports/1" } ]
    )

    html = active_job_notifications(for: user)

    assert_match(/View report/, html)
    assert_match(%r{/reports/1}, html)

    notification.destroy
    user.destroy
  end
end
