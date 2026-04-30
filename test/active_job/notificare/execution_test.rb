require "test_helper"

class ActiveJob::Notificare::ExecutionTest < ActiveSupport::TestCase
  def build_execution(overrides = {})
    ActiveJob::Notificare::Execution.new(
      { job_id: SecureRandom.uuid, job_class: "SomeJob", status: "enqueued" }.merge(overrides)
    )
  end

  # validations

  test "valid with required attributes" do
    assert build_execution.valid?
  end

  test "invalid without job_id" do
    assert_not build_execution(job_id: nil).valid?
  end

  test "invalid without job_class" do
    assert_not build_execution(job_class: nil).valid?
  end

  test "invalid without status" do
    e = build_execution
    e.status = nil
    assert_not e.valid?
  end

  test "job_id must be unique" do
    id = SecureRandom.uuid
    ActiveJob::Notificare::Execution.create!(job_id: id, job_class: "SomeJob", status: "enqueued")
    assert_not build_execution(job_id: id).valid?
  end

  # status enum

  test "status enum has all expected values" do
    assert_equal %w[enqueued running completed failed], ActiveJob::Notificare::Execution.statuses.keys
  end

  test "enqueued? predicate" do
    assert build_execution(status: "enqueued").enqueued?
  end

  test "running? predicate" do
    assert build_execution(status: "running").running?
  end

  test "completed? predicate" do
    assert build_execution(status: "completed").completed?
  end

  test "failed? predicate" do
    assert build_execution(status: "failed").failed?
  end

  # scopes

  test "recent scope orders by created_at desc" do
    first  = ActiveJob::Notificare::Execution.create!(job_id: SecureRandom.uuid, job_class: "J", status: "enqueued", created_at: 2.minutes.ago)
    second = ActiveJob::Notificare::Execution.create!(job_id: SecureRandom.uuid, job_class: "J", status: "enqueued", created_at: 1.minute.ago)
    assert_equal [ second.id, first.id ], ActiveJob::Notificare::Execution.recent.map(&:id)
  end

  test "running scope returns only running executions" do
    ActiveJob::Notificare::Execution.create!(job_id: SecureRandom.uuid, job_class: "J", status: "running")
    ActiveJob::Notificare::Execution.create!(job_id: SecureRandom.uuid, job_class: "J", status: "completed")
    assert_equal 1, ActiveJob::Notificare::Execution.running.count
    assert ActiveJob::Notificare::Execution.running.first.running?
  end

  test "failed scope returns only failed executions" do
    ActiveJob::Notificare::Execution.create!(job_id: SecureRandom.uuid, job_class: "J", status: "failed")
    ActiveJob::Notificare::Execution.create!(job_id: SecureRandom.uuid, job_class: "J", status: "enqueued")
    assert_equal 1, ActiveJob::Notificare::Execution.failed.count
    assert ActiveJob::Notificare::Execution.failed.first.failed?
  end
end
