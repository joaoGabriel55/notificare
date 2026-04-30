require "test_helper"

class ActiveJob::Notificare::ProjectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  # --- unit: instrument events directly ---

  test "enqueue event creates an execution row with enqueued status" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.enqueued?
    assert_equal "TrackedTestJob", execution.job_class
  end

  test "perform_start event transitions to running" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.running?
    assert_not_nil execution.started_at
  end

  test "perform event transitions to completed" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job)
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.completed?
    assert_not_nil execution.completed_at
  end

  test "perform event with exception transitions to failed with error" do
    job = TrackedTestJob.new
    error = StandardError.new("boom")
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job, exception_object: error)
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.failed?
    assert_equal "boom", execution.error
    assert_not_nil execution.completed_at
  end

  test "creates exactly one execution row per job_id even with duplicate enqueue events" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("enqueue.active_job", job: job)
    assert_equal 1, ActiveJob::Notificare::Execution.where(job_id: job.job_id).count
  end

  # --- negative: untracked job produces no rows ---

  test "job without tracks_progress? produces no execution row" do
    job = UntrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job)
    assert_equal 0, ActiveJob::Notificare::Execution.count
  end

  # --- integration: jobs performed via inline adapter ---

  test "perform_later produces full enqueued → running → completed transition" do
    assert_difference -> { ActiveJob::Notificare::Execution.count }, +1 do
      TrackedTestJob.perform_later
    end
    perform_enqueued_jobs
    execution = ActiveJob::Notificare::Execution.order(created_at: :desc).first
    assert execution.completed?
    assert_not_nil execution.started_at
    assert_not_nil execution.completed_at
  end

  test "perform_later for a failing job transitions to failed" do
    FailingTrackedTestJob.perform_later
    assert_raises(StandardError) { perform_enqueued_jobs }
    execution = ActiveJob::Notificare::Execution.order(created_at: :desc).first
    assert execution.failed?
    assert_equal "something went wrong", execution.error
    assert_not_nil execution.completed_at
  end

  test "untracked job with perform_later produces zero rows" do
    UntrackedTestJob.perform_later
    perform_enqueued_jobs
    assert_equal 0, ActiveJob::Notificare::Execution.count
  end

  # --- continuable: step tracking ---

  test "step_started event updates current_step" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:import_rows))
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert_equal "import_rows", execution.current_step
  end

  test "current_step advances across step boundaries" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)

    instrument("step_started.active_job", job: job, step: fake_step(:validate))
    assert_equal "validate", ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).current_step

    instrument("step_started.active_job", job: job, step: fake_step(:process_rows))
    assert_equal "process_rows", ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).current_step

    instrument("step_started.active_job", job: job, step: fake_step(:notify))
    assert_equal "notify", ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).current_step
  end

  # --- continuable: resume semantics (ERD §9 case 3) ---

  test "crash resume reuses existing execution row without creating a second one" do
    job = TrackedTestJob.new

    # First run: enqueue and start
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:fetch_data))

    # Simulate worker kill: perform.active_job never fires; status stays running.
    assert_equal "running", ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).status

    # Continuable re-enqueues with the same job_id.
    assert_no_difference -> { ActiveJob::Notificare::Execution.count } do
      instrument("enqueue.active_job", job: job)
    end

    # Resume run: perform_start fires again for the same job_id.
    instrument("perform_start.active_job", job: job)
    instrument("step_started.active_job", job: job, step: fake_step(:process_rows))
    instrument("perform.active_job", job: job)

    assert_equal 1, ActiveJob::Notificare::Execution.where(job_id: job.job_id).count
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.completed?
    assert_equal "process_rows", execution.current_step
  end

  test "resume preserves progress_current and started_at when status is running" do
    job = TrackedTestJob.new

    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    original_started_at = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).started_at

    # Simulate partial progress already recorded
    ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).update!(progress_current: 42)

    # Worker killed; re-enqueue + resume
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)

    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert_equal 42, execution.progress_current
    assert_in_delta original_started_at.to_f, execution.started_at.to_f, 0.001
  end

  test "resume clears stale error when status is running" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).update!(error: "stale error from previous attempt")

    # Re-enqueue + resume
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)

    assert_nil ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id).error
  end

  # --- race condition: find_or_create_by! uniqueness ---

  test "enqueue handler is idempotent when row already exists (simulates race loser)" do
    job = TrackedTestJob.new
    # Simulate winning thread having already created the row
    ActiveJob::Notificare::Execution.create!(
      job_id: job.job_id,
      job_class: "TrackedTestJob",
      status: "enqueued"
    )

    assert_no_difference -> { ActiveJob::Notificare::Execution.count } do
      instrument("enqueue.active_job", job: job)
    end
  end

  private

  def instrument(event, payload = {})
    ActiveSupport::Notifications.instrument(event, payload)
  end

  def fake_step(name)
    Struct.new(:name).new(name)
  end
end
