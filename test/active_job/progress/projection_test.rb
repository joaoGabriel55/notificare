require "test_helper"

class ActiveJob::Progress::ProjectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    ActiveJob::Progress::Projection.unsubscribe!
    ActiveJob::Progress::Projection.subscribe!
  end

  teardown do
    ActiveJob::Progress::Projection.unsubscribe!
  end

  # --- unit: instrument events directly ---

  test "enqueue event creates an execution row with enqueued status" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    execution = ActiveJob::Progress::Execution.find_by!(job_id: job.job_id)
    assert execution.enqueued?
    assert_equal "TrackedTestJob", execution.job_class
  end

  test "perform_start event transitions to running" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    execution = ActiveJob::Progress::Execution.find_by!(job_id: job.job_id)
    assert execution.running?
    assert_not_nil execution.started_at
  end

  test "perform event transitions to completed" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job)
    execution = ActiveJob::Progress::Execution.find_by!(job_id: job.job_id)
    assert execution.completed?
    assert_not_nil execution.completed_at
  end

  test "perform event with exception transitions to failed with error" do
    job = TrackedTestJob.new
    error = StandardError.new("boom")
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job, exception_object: error)
    execution = ActiveJob::Progress::Execution.find_by!(job_id: job.job_id)
    assert execution.failed?
    assert_equal "boom", execution.error
    assert_not_nil execution.completed_at
  end

  test "creates exactly one execution row per job_id even with duplicate enqueue events" do
    job = TrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("enqueue.active_job", job: job)
    assert_equal 1, ActiveJob::Progress::Execution.where(job_id: job.job_id).count
  end

  # --- negative: untracked job produces no rows ---

  test "job without tracks_progress? produces no execution row" do
    job = UntrackedTestJob.new
    instrument("enqueue.active_job", job: job)
    instrument("perform_start.active_job", job: job)
    instrument("perform.active_job", job: job)
    assert_equal 0, ActiveJob::Progress::Execution.count
  end

  # --- integration: jobs performed via inline adapter ---

  test "perform_later produces full enqueued → running → completed transition" do
    assert_difference -> { ActiveJob::Progress::Execution.count }, +1 do
      TrackedTestJob.perform_later
    end
    perform_enqueued_jobs
    execution = ActiveJob::Progress::Execution.order(created_at: :desc).first
    assert execution.completed?
    assert_not_nil execution.started_at
    assert_not_nil execution.completed_at
  end

  test "perform_later for a failing job transitions to failed" do
    FailingTrackedTestJob.perform_later
    assert_raises(StandardError) { perform_enqueued_jobs }
    execution = ActiveJob::Progress::Execution.order(created_at: :desc).first
    assert execution.failed?
    assert_equal "something went wrong", execution.error
    assert_not_nil execution.completed_at
  end

  test "untracked job with perform_later produces zero rows" do
    UntrackedTestJob.perform_later
    perform_enqueued_jobs
    assert_equal 0, ActiveJob::Progress::Execution.count
  end

  private

  def instrument(event, payload = {})
    ActiveSupport::Notifications.instrument(event, payload)
  end
end
