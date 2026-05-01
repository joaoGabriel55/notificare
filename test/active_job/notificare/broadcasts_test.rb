require "test_helper"

class ActiveJob::Notificare::BroadcastsTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
    @user = User.create!(name: "Test User")
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  # --- Unit: stream name format — pin so refactors are caught ---

  test "execution broadcast stream name is active_job_progress colon job_id" do
    execution = ActiveJob::Notificare::Execution.create!(
      job_id: "pinned-stream-job-id",
      job_class: "TestJob",
      status: "enqueued"
    )

    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      execution.update!(status: "running")
    end

    assert_equal "active_job_progress:pinned-stream-job-id", enqueued_jobs.last[:args][0]
  end

  test "notification broadcast stream name is active_job_notifications colon recipient_gid_param" do
    notification = ActiveJob::Notificare::Notification.create!(
      recipient: @user,
      event_type: "completed",
      title: "Test"
    )
    clear_enqueued_jobs

    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      notification.update!(read_at: Time.current)
    end

    assert_equal "active_job_notifications:#{@user.to_gid_param}", enqueued_jobs.last[:args][0]
  end

  # --- Unit: BroadcastStreamJob is enqueued on model changes ---

  test "updating progress_current enqueues a turbo broadcast job" do
    execution = ActiveJob::Notificare::Execution.create!(
      job_id: "broadcast-enqueue-test",
      job_class: "TestJob",
      status: "running"
    )
    clear_enqueued_jobs

    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      execution.update!(progress_current: 5)
    end
  end

  test "inserting a notification enqueues a turbo broadcast job" do
    assert_enqueued_with(job: Turbo::Streams::BroadcastStreamJob) do
      ActiveJob::Notificare::Notification.create!(
        recipient: @user,
        event_type: "completed",
        title: "Done"
      )
    end
  end

  # --- Acceptance: broadcasts reach ActionCable ---

  test "updating progress_current produces a turbo stream broadcast" do
    execution = ActiveJob::Notificare::Execution.create!(
      job_id: "cable-progress-test",
      job_class: "TestJob",
      status: "running"
    )
    stream = "active_job_progress:cable-progress-test"

    assert_broadcasts stream, 1 do
      perform_enqueued_jobs { execution.update!(progress_current: 3) }
    end
  end

  test "inserting a notification broadcasts to the recipient inbox stream" do
    stream = "active_job_notifications:#{@user.to_gid_param}"

    assert_broadcasts stream, 1 do
      perform_enqueued_jobs do
        ActiveJob::Notificare::Notification.create!(
          recipient: @user,
          event_type: "completed",
          title: "Done"
        )
      end
    end
  end

  # --- Negative: no broadcast when tracks_progress not declared ---

  test "untracked job produces no execution row and no broadcast on its would-be stream" do
    hypothetical_job = UntrackedTestJob.new
    stream = "active_job_progress:#{hypothetical_job.job_id}"

    perform_enqueued_jobs { UntrackedTestJob.perform_later }

    assert_equal 0, ActiveJob::Notificare::Execution.count
    assert_empty broadcasts(stream)
  end

  # --- Integration: end-to-end from real job run via Action Cable test adapter ---

  test "tracked job run produces at least one turbo stream broadcast on execution stream" do
    TrackedTestJob.perform_later
    execution = ActiveJob::Notificare::Execution.order(created_at: :desc).first
    stream = "active_job_progress:#{execution.job_id}"

    perform_enqueued_jobs

    assert broadcasts(stream).any?, "Expected at least one broadcast on #{stream}, but got none"
  end

  test "job with notify_on broadcasts a notification to recipient inbox on completion" do
    stream = "active_job_notifications:#{@user.to_gid_param}"
    NotifyOnTestJob.perform_later(recipient: @user)

    # First flush runs NotifyOnTestJob (writes Notification, queues BroadcastStreamJob).
    # Second flush runs BroadcastStreamJob so the broadcast reaches ActionCable.
    perform_enqueued_jobs
    perform_enqueued_jobs

    assert broadcasts(stream).any?, "Expected at least one broadcast on #{stream}, but got none"
  end
end
