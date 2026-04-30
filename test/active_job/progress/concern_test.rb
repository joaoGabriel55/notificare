require "test_helper"

class ActiveJob::Progress::ConcernTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Progress::Projection.unsubscribe!
    ActiveJob::Progress::Projection.subscribe!
  end

  teardown do
    ActiveJob::Progress::Projection.unsubscribe!
  end

  test "tracks_progress macro sets tracks_progress? to true" do
    job_class = Class.new(ApplicationJob) { include ActiveJob::Progress; tracks_progress }
    assert job_class.tracks_progress?
  end

  test "job without tracks_progress macro returns falsy for tracks_progress?" do
    job_class = Class.new(ApplicationJob) { include ActiveJob::Progress }
    assert_not job_class.tracks_progress?
  end

  test "tracks_progress? is independent per class" do
    parent = Class.new(ApplicationJob) { include ActiveJob::Progress; tracks_progress }
    child  = Class.new(parent)
    assert parent.tracks_progress?
    assert_not child.tracks_progress?
  end

  test "progress returns a ProgressHandle instance" do
    job = ProgressDslTestJob.new
    assert_instance_of ActiveJob::Progress::ProgressHandle, job.progress
  end

  test "progress is memoized" do
    job = ProgressDslTestJob.new
    assert_same job.progress, job.progress
  end

  test "DSL job completes with correct progress_current and progress_total" do
    ProgressDslTestJob.perform_later
    perform_enqueued_jobs
    execution = ActiveJob::Progress::Execution.order(created_at: :desc).first
    assert_equal 10, execution.progress_current
    assert_equal 10, execution.progress_total
  end
end
