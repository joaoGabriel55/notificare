require "test_helper"

# Failure & Recovery test suite — ERD §9 + §11 (Ticket 13)
# Each case number refers to ERD §9's numbered failure scenarios.
class ActiveJob::Notificare::FailureRecoveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
    @user = User.create!(name: "Recovery Test User")
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  # --- Worker killed mid-step (simulated: perform.active_job never fires) ---

  test "worker killed mid-step: no duplicate execution row on re-enqueue" do
    job = ProgressDslTestJob.new

    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:fetch_data))

    # Worker killed — perform.active_job never fires; row stays running.
    assert_equal "running", execution_for(job).status

    assert_no_difference -> { ActiveJob::Notificare::Execution.count } do
      instrument("enqueue.active_job", job: job)
    end

    assert_equal 1, ActiveJob::Notificare::Execution.where(job_id: job.job_id).count
  end

  test "worker killed mid-step: progress_current continues from persisted value after resume" do
    job = ProgressDslTestJob.new

    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:fetch_data))

    ActiveJob::Notificare::Execution.where(job_id: job.job_id).update_all(progress_current: 42)

    # Re-enqueue and resume
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)

    assert_equal 42, execution_for(job).progress_current
  end

  test "worker killed mid-step: current_step is accurate after resume picks up new step" do
    job = ProgressDslTestJob.new

    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:fetch_data))

    # Simulate kill: no perform.active_job fires.
    # Continuation re-enqueues with the same job_id.
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:process_rows))

    assert_equal "process_rows", execution_for(job).current_step
  end

  # --- Concurrent updates ---

  test "concurrent advance! calls with interleaved status transition are all recorded without loss" do
    job = ProgressDslTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    execution = execution_for(job)

    advance_threads = Array.new(10) do
      Thread.new { 100.times { ActiveJob::Notificare::ProgressHandle.new(job.job_id).advance! } }
    end

    # One thread transitions status to completed while advances are in flight.
    transition_thread = Thread.new do
      execution.reload.update!(status: "completed", completed_at: Time.current)
    end

    (advance_threads + [ transition_thread ]).each(&:join)

    final = execution_for(job)
    assert_equal "completed", final.status
    assert_equal 1000, final.progress_current,
      "update_all SQL increment must not lose concurrent updates"
  end

  # --- ERD §9 case 1: no tracks_progress ---

  test "case 1 no_tracks_progress: full lifecycle produces zero rows in execution table" do
    UntrackedTestJob.perform_later
    perform_enqueued_jobs
    assert_equal 0, ActiveJob::Notificare::Execution.count
  end

  test "case 1 no_tracks_progress: full lifecycle produces zero rows in notifications table" do
    UntrackedTestJob.perform_later
    perform_enqueued_jobs
    assert_equal 0, ActiveJob::Notificare::Notification.count
  end

  test "case 1 no_tracks_progress: instrumenting all events produces zero rows in both tables" do
    job = UntrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job)
    assert_equal 0, ActiveJob::Notificare::Execution.count
    assert_equal 0, ActiveJob::Notificare::Notification.count
  end

  # --- ERD §9 case 2: indeterminate progress ---

  test "case 2 indeterminate_progress: lifecycle completes and progress_total stays nil" do
    TrackedTestJob.perform_later
    perform_enqueued_jobs
    execution = ActiveJob::Notificare::Execution.order(created_at: :desc).first
    assert execution.completed?
    assert_nil execution.progress_total,
      "expected progress_total to stay nil for an indeterminate job"
  end

  test "case 2 indeterminate_progress: execution row exists with nil total for spinner helper" do
    # Verifies the execution state that causes active_job_notificare to render a spinner.
    # Spinner rendering itself is covered by view_helpers_test.rb.
    job = ProgressDslTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)

    execution = execution_for(job)
    assert_nil execution.progress_total
    assert execution.running?
  end

  # --- ERD §9 case 3: resume reuses row (integration level) ---

  test "case 3 resume_reuses_row: same execution row found after worker kill and re-enqueue" do
    job = TrackedTestJob.new

    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    row_id = execution_for(job).id

    # Simulate kill: perform.active_job never fires.
    assert_no_difference -> { ActiveJob::Notificare::Execution.count } do
      instrument("enqueue.active_job", job: job)
    end

    assert_equal row_id, execution_for(job).id,
      "resume must reuse the existing DB row, not create a new one"
  end

  test "case 3 resume_reuses_row: started_at is preserved across worker kill and resume" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    original_started_at = execution_for(job).started_at

    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)

    assert_in_delta original_started_at.to_f, execution_for(job).started_at.to_f, 0.001,
      "started_at must be preserved (not reset) on resume"
  end

  test "case 3 resume_reuses_row: completes to a single execution row" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job)

    assert_equal 1, ActiveJob::Notificare::Execution.where(job_id: job.job_id).count
    assert execution_for(job).completed?
  end

  # --- ERD §9 case 4: missing recipient ---

  test "case 4 missing_recipient: ArgumentError raised before adapter enqueues the job" do
    # Spy on adapter: assert the specific job class never lands in the enqueued_jobs
    # list (even though enqueue.active_job fires in ensure and a BroadcastStreamJob
    # may be queued from the Execution row's after_commit).
    assert_no_enqueued_jobs(only: NotifyOnTestJob) do
      assert_raises(ArgumentError) { NotifyOnTestJob.perform_later }
    end
  end

  test "case 4 missing_recipient: error message identifies the job class and missing kwarg" do
    error = assert_raises(ArgumentError) { NotifyOnTestJob.perform_later }
    assert_match(/NotifyOnTestJob/, error.message)
    assert_match(/recipient/, error.message)
  end

  test "case 4 missing_recipient: uses_notify! job raises before adapter enqueues" do
    # UsesNotifyTestJob calls uses_notify! at class definition, so enforcement is
    # immediate — even before any instance has run perform.
    assert_no_enqueued_jobs(only: UsesNotifyTestJob) do
      assert_raises(ArgumentError) { UsesNotifyTestJob.perform_later }
    end
  end

  # --- ERD §9 case 5: manual notify after completion ---

  test "case 5 manual_notify_after_completion: notification row is written with correct attributes" do
    job = ManualNotifyTestJob.new
    job.recipient = @user

    assert_difference -> { ActiveJob::Notificare::Notification.count }, +1 do
      job.notify(title: "Post-completion notice", description: "written after perform finishes")
    end

    notification = ActiveJob::Notificare::Notification.last
    assert notification.custom?
    assert_equal "Post-completion notice", notification.title
    assert_equal "written after perform finishes", notification.description
    assert_equal @user, notification.recipient
    assert_equal job.job_id, notification.job_id
  end

  test "case 5 manual_notify_after_completion: broadcast fires on recipient inbox stream" do
    stream = "active_job_notifications:#{@user.to_gid_param}"
    job = ManualNotifyTestJob.new
    job.recipient = @user

    assert_broadcasts stream, 1 do
      perform_enqueued_jobs do
        job.notify(title: "Broadcast test after completion")
      end
    end
  end

  test "case 5 manual_notify_after_completion: notify without recipient silently skips row and broadcast" do
    job = ManualNotifyTestJob.new

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      job.notify(title: "No recipient — should be a no-op")
    end
  end

  # --- V1 documented behavior: duplicate failed notifications on retry ---
  #
  # This test ASSERTS the current (non-idempotent) v1 behavior.  When idempotency
  # lands, this test should be updated deliberately (not silently broken).

  test "v1_duplicate_failed_notifications: retried failure writes a second failed notification row" do
    job = FailingNotifyOnTestJob.new
    job.recipient = @user

    # First attempt: enqueue → start → fail
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job, exception_object: StandardError.new("notify_on failure"))

    after_first = ActiveJob::Notificare::Notification.where(event_type: "failed", job_id: job.job_id).count
    assert_equal 1, after_first

    # Retry attempt (same job_id): Continuation re-enqueues, job fails again.
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job, exception_object: StandardError.new("notify_on failure"))

    after_retry = ActiveJob::Notificare::Notification.where(event_type: "failed", job_id: job.job_id).count
    # v1: second failure appends another 'failed' row — idempotency not yet implemented.
    assert_equal 2, after_retry,
      "v1 behavior: each failed attempt writes a notification row; update this test when idempotency ships"
  end

  private

  def instrument(event, payload = {})
    ActiveSupport::Notifications.instrument(event, payload)
  end

  def fake_step(name)
    Struct.new(:name).new(name)
  end

  def execution_for(job)
    ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
  end
end
