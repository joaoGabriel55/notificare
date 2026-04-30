require "test_helper"

class ActiveJob::Notificare::ConcernTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  test "including the module sets tracks_progress? to true by default (opt-in via include)" do
    job_class = Class.new(ApplicationJob) { include ActiveJob::Notificare }
    assert job_class.tracks_progress?
  end

  test "tracks_progress(false) opts out without removing the include" do
    job_class = Class.new(ApplicationJob) do
      include ActiveJob::Notificare
      tracks_progress false
    end
    assert_not job_class.tracks_progress?
  end

  test "tracks_progress? is independent per class" do
    parent = Class.new(ApplicationJob) { include ActiveJob::Notificare }
    child  = Class.new(parent) { tracks_progress false }
    assert parent.tracks_progress?
    assert_not child.tracks_progress?
  end

  test "including the module auto-includes ActiveJob::Continuable" do
    job_class = Class.new(ApplicationJob) { include ActiveJob::Notificare }
    assert_includes job_class.ancestors, ActiveJob::Continuable
  end

  test "progress returns a ProgressHandle instance" do
    job = ProgressDslTestJob.new
    assert_instance_of ActiveJob::Notificare::ProgressHandle, job.progress
  end

  test "progress is memoized" do
    job = ProgressDslTestJob.new
    assert_same job.progress, job.progress
  end

  test "DSL job completes with correct progress_current and progress_total" do
    ProgressDslTestJob.perform_later
    perform_enqueued_jobs
    execution = ActiveJob::Notificare::Execution.order(created_at: :desc).first
    assert_equal 10, execution.progress_current
    assert_equal 10, execution.progress_total
  end
end
