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

  test "step.active_job does not write a notification row when job has no recipient" do
    job = StepDslTestJob.new
    job.send(:step, :validate, notify: :validated) { :ok }

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      step = Struct.new(:name).new(:validate)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end
  end

  test "step.active_job does not write a row when no notify: was declared for the step" do
    job = StepDslTestJob.new
    job.send(:step, :foo) { :ok }

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      step = Struct.new(:name).new(:foo)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end
  end

  test "untracked job does not write a notification row on step.active_job" do
    job = UntrackedTestJob.new

    assert_no_difference -> { ActiveJob::Notificare::Notification.count } do
      step = Struct.new(:name).new(:foo)
      ActiveSupport::Notifications.instrument("step.active_job", job: job, step: step, interrupted: false)
    end
  end
end
