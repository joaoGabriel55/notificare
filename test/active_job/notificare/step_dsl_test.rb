require "test_helper"

class ActiveJob::Notificare::StepDslTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
  end

  test "step with notify: stashes the event on the job instance" do
    job = StepDslTestJob.new
    job.send(:step, :foo, notify: :foo_done) { :ok }
    assert_equal :foo_done, job.notificare_step_notify_for(:foo)
  end

  test "step without notify: leaves the stash empty for that step" do
    job = StepDslTestJob.new
    job.send(:step, :bare) { :ok }
    assert_nil job.notificare_step_notify_for(:bare)
  end

  test "notificare_step_notify_for returns nil when nothing was stashed" do
    job = StepDslTestJob.new
    assert_nil job.notificare_step_notify_for(:never_set)
  end

  test "step_completed.active_job logs the would-write notification when notify: was declared" do
    job = StepDslTestJob.new
    job.send(:step, :validate, notify: :validated) { :ok }

    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log_output, level: Logger::DEBUG)
    begin
      step = Struct.new(:name).new(:validate)
      ActiveSupport::Notifications.instrument("step_completed.active_job", job: job, step: step)
    ensure
      Rails.logger = original_logger
    end
    assert_match(/would-write notification event=:validated/, log_output.string)
  end

  test "step_completed.active_job is silent when no notify: was declared for the step" do
    job = StepDslTestJob.new
    job.send(:step, :foo) { :ok }

    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log_output, level: Logger::DEBUG)
    begin
      step = Struct.new(:name).new(:foo)
      ActiveSupport::Notifications.instrument("step_completed.active_job", job: job, step: step)
    ensure
      Rails.logger = original_logger
    end
    refute_match(/would-write notification/, log_output.string)
  end

  test "untracked job does not trigger step_completed handler" do
    job = UntrackedTestJob.new
    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = Logger.new(log_output, level: Logger::DEBUG)
    begin
      step = Struct.new(:name).new(:foo)
      ActiveSupport::Notifications.instrument("step_completed.active_job", job: job, step: step)
    ensure
      Rails.logger = original_logger
    end
    refute_match(/would-write notification/, log_output.string)
  end
end
