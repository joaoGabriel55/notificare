require "test_helper"

class ActiveJob::Notificare::ExecutionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ActiveJob::Notificare.authenticate_with = -> { true }

    @execution = ActiveJob::Notificare::Execution.create!(
      job_id: SecureRandom.uuid,
      job_class: "ImportJob",
      status: "completed",
      progress_current: 10,
      progress_total: 10
    )
    @running = ActiveJob::Notificare::Execution.create!(
      job_id: SecureRandom.uuid,
      job_class: "ExportJob",
      status: "running"
    )
    @failed = ActiveJob::Notificare::Execution.create!(
      job_id: SecureRandom.uuid,
      job_class: "ImportJob",
      status: "failed",
      error: "Something went wrong"
    )
  end

  teardown do
    ActiveJob::Notificare.authenticate_with = nil
    ActiveJob::Notificare::Execution.delete_all
    ActiveJob::Notificare::Notification.delete_all
  end

  # --- Routing ---

  test "GET /executions is recognized as executions#index" do
    assert_recognizes(
      { controller: "active_job/notificare/executions", action: "index" },
      { path: "/notificare/executions", method: :get }
    )
  end

  test "GET /executions/:id is recognized as executions#show" do
    assert_recognizes(
      { controller: "active_job/notificare/executions", action: "show", id: "1" },
      { path: "/notificare/executions/1", method: :get }
    )
  end

  # --- Index ---

  test "GET index returns 200" do
    get notificare.executions_path
    assert_response :ok
  end

  test "GET index lists executions" do
    get notificare.executions_path
    assert_select "table.nf-table"
    assert_select "td", text: "ImportJob"
    assert_select "td", text: "ExportJob"
  end

  test "GET index filters by status" do
    get notificare.executions_path(status: "running")
    assert_response :ok
    assert_select "td", text: "ExportJob"
    assert_select "td", count: 0, text: "ImportJob"
  end

  test "GET index filters by job_class" do
    get notificare.executions_path(job_class: "ImportJob")
    assert_response :ok
    assert_select "td", text: "ImportJob"
    assert_select "td", count: 0, text: "ExportJob"
  end

  test "GET index shows empty state when no results" do
    get notificare.executions_path(status: "enqueued")
    assert_response :ok
    assert_select ".nf-empty"
  end

  test "GET index paginates results" do
    stub_const(ActiveJob::Notificare::ExecutionsController, :PER_PAGE, 2) do
      get notificare.executions_path
      assert_response :ok
      assert_select ".nf-pagination"
    end
  end

  test "GET index page 2 returns correct offset" do
    stub_const(ActiveJob::Notificare::ExecutionsController, :PER_PAGE, 2) do
      get notificare.executions_path(page: 2)
      assert_response :ok
      assert_select "table.nf-table"
    end
  end

  # --- Show ---

  test "GET show returns 200" do
    get notificare.execution_path(@execution)
    assert_response :ok
  end

  test "GET show displays job details" do
    get notificare.execution_path(@execution)
    assert_select "h1", text: "ImportJob"
    assert_select ".nf-badge--completed"
    assert_select ".nf-kv"
  end

  test "GET show displays live progress widget" do
    get notificare.execution_path(@running)
    assert_select "turbo-cable-stream-source"
  end

  test "GET show displays error for failed execution" do
    get notificare.execution_path(@failed)
    assert_select ".nf-error", text: /Something went wrong/
  end

  test "GET show lists notifications tied to job" do
    ActiveJob::Notificare::Notification.create!(
      job_id: @execution.job_id,
      recipient: User.create!(name: "Tester"),
      event_type: "completed",
      title: "Import finished"
    )

    get notificare.execution_path(@execution)
    assert_response :ok
    assert_select "td", text: "Import finished"
  end

  test "GET show returns 404 for unknown id" do
    get notificare.execution_path(id: 999_999)
    assert_response :not_found
  end

  # --- Authentication ---

  test "production without authenticate_with configured returns 403" do
    ActiveJob::Notificare.authenticate_with = nil
    saved_env = Rails.env
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    get notificare.executions_path
    assert_response :forbidden
  ensure
    Rails.instance_variable_set(:@_env, saved_env)
  end

  test "non-production without authenticate_with configured returns 200" do
    ActiveJob::Notificare.authenticate_with = nil
    get notificare.executions_path
    assert_response :ok
  end

  test "authenticate_with proc returning false returns 403" do
    ActiveJob::Notificare.authenticate_with = -> { false }
    get notificare.executions_path
    assert_response :forbidden
  end

  test "authenticate_with proc returning true returns 200" do
    ActiveJob::Notificare.authenticate_with = -> { true }
    get notificare.executions_path
    assert_response :ok
  end

  test "authenticate_with proc returning false blocks show too" do
    ActiveJob::Notificare.authenticate_with = -> { false }
    get notificare.execution_path(@execution)
    assert_response :forbidden
  end

  private

  def stub_const(object, const, value)
    old = object.const_get(const)
    object.send(:remove_const, const)
    object.const_set(const, value)
    yield
  ensure
    object.send(:remove_const, const)
    object.const_set(const, old)
  end
end
