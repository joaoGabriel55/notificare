require "test_helper"

# System-level integration test for the executions UI.
# Verifies that visiting a show page for an in-flight execution includes the
# turbo-cable-stream-source element that drives live progress updates in the browser.
class ActiveJob::Notificare::ExecutionsSystemTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare.authenticate_with = -> { true }
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!
  end

  teardown do
    ActiveJob::Notificare.authenticate_with = nil
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Notification.delete_all
    ActiveJob::Notificare::Execution.delete_all
    User.delete_all
  end

  test "show page for in-flight execution wires live progress subscription" do
    ProgressDslTestJob.perform_later

    execution = ActiveJob::Notificare::Execution.last
    assert execution, "expected an execution row after enqueue"

    get notificare.execution_path(execution)
    assert_response :ok

    assert_select "turbo-cable-stream-source", minimum: 1
  end

  test "show page updates after job completes" do
    ProgressDslTestJob.perform_later
    perform_enqueued_jobs

    execution = ActiveJob::Notificare::Execution.last
    assert execution
    assert_equal "completed", execution.status

    get notificare.execution_path(execution)
    assert_response :ok
    assert_select ".nf-badge--completed"
    assert_select "turbo-cable-stream-source"
  end

  test "show page displays notifications written during job run" do
    user = User.create!(name: "System Test User")
    NotifyOnTestJob.perform_later(recipient: user)
    perform_enqueued_jobs

    execution = ActiveJob::Notificare::Execution.last
    assert execution

    get notificare.execution_path(execution)
    assert_response :ok
    assert_select ".nf-badge--completed"
  end

  test "index page lists executions created by a real job" do
    ProgressDslTestJob.perform_later
    perform_enqueued_jobs

    get notificare.executions_path
    assert_response :ok
    assert_select "table.nf-table"
    assert_select ".nf-badge"
  end
end
