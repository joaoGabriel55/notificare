require "test_helper"

class ActiveJob::Notificare::ProgressHandleTest < ActiveSupport::TestCase
  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
    @job = ProgressDslTestJob.new
    ActiveSupport::Notifications.instrument("enqueue.active_job", job: @job)
    ActiveSupport::Notifications.instrument("perform_start.active_job", job: @job)
    @handle = ActiveJob::Notificare::ProgressHandle.new(@job.job_id)
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  test "total sets progress_total on the execution row" do
    @handle.total(100)
    assert_equal 100, execution.progress_total
  end

  test "advance! increments progress_current by 1 by default" do
    @handle.advance!
    assert_equal 1, execution.progress_current
  end

  test "advance! increments by custom step" do
    @handle.advance!(5)
    assert_equal 5, execution.progress_current
  end

  test "100 advance! calls leave progress_current at 100" do
    100.times { @handle.advance! }
    assert_equal 100, execution.progress_current
  end

  test "advance! no-ops gracefully before execution row exists" do
    handle = ActiveJob::Notificare::ProgressHandle.new("nonexistent-job-id")
    assert_nothing_raised { handle.advance! }
    assert_equal 0, ActiveJob::Notificare::Execution.where(job_id: "nonexistent-job-id").count
  end

  test "total no-ops gracefully before execution row exists" do
    handle = ActiveJob::Notificare::ProgressHandle.new("nonexistent-job-id")
    assert_nothing_raised { handle.total(50) }
    assert_equal 0, ActiveJob::Notificare::Execution.where(job_id: "nonexistent-job-id").count
  end

  test "concurrent advance! calls from 10 threads yield correct final count" do
    threads = Array.new(10) { Thread.new { 100.times { @handle.advance! } } }
    threads.each(&:join)
    assert_equal 1000, execution.progress_current
  end

  private

  def execution
    ActiveJob::Notificare::Execution.find_by!(job_id: @job.job_id)
  end
end
