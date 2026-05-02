require "test_helper"

# Smoke test: exercises the pre-generated scaffold for ScaffoldDemoJob.
# It verifies the generated controller/views boot, and that running the job
# surfaces progress + notification markup on the index and show pages.
class ActiveJob::Notificare::ScaffoldSmokeTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Projection.subscribe!

    @user = User.create!(name: "Demo User")
    session_for_user(@user)
  end

  teardown do
    ActiveJob::Notificare::Projection.unsubscribe!
    ActiveJob::Notificare::Execution.delete_all
    ActiveJob::Notificare::Notification.delete_all
    User.delete_all
  end

  test "GET /scaffold_demos renders index and shows no executions before job runs" do
    get scaffold_demos_path
    assert_response :ok
    # h1 and empty state are driven by locale keys — assert the translated values
    assert_select "h1", I18n.t("scaffold_demos.index.title")
    assert_select "p", text: I18n.t("scaffold_demos.index.empty")
  end

  test "index shows execution progress after job runs" do
    ScaffoldDemoJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    get scaffold_demos_path
    assert_response :ok
    assert_select ".notificare-progress"
  end

  test "index renders notification inbox for current recipient" do
    get scaffold_demos_path
    assert_response :ok
    assert_select "#active_job_notifications"
  end

  test "GET /scaffold_demos/:id shows execution detail with progress widget" do
    ScaffoldDemoJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    execution = ActiveJob::Notificare::Execution.find_by!(job_class: "ScaffoldDemoJob")

    get scaffold_demo_path(execution)
    assert_response :ok
    assert_select "h1", I18n.t("scaffold_demos.show.title")
    assert_select ".notificare-progress"
    assert_select "h2", I18n.t("scaffold_demos.show.progress_heading")
    assert_select "h2", I18n.t("scaffold_demos.show.notifications_heading")
  end

  test "show page lists notifications for the job run" do
    ScaffoldDemoJob.perform_later(recipient: @user)
    perform_enqueued_jobs

    execution = ActiveJob::Notificare::Execution.find_by!(job_class: "ScaffoldDemoJob")

    get scaffold_demo_path(execution)
    assert_response :ok
    assert_select ".notificare-notification"
  end

  test "show returns 404 for unknown execution id" do
    get scaffold_demo_path(id: 0)
    assert_response :not_found
  end

  private

  def session_for_user(user)
    # Set session[:user_id] via the home controller so ApplicationController
    # resolves current_notificare_recipient correctly for subsequent requests.
    get home_path(user_id: user.id)
  end
end
