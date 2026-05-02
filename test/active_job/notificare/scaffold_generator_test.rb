require "test_helper"
require "generators/active_job/notificare/scaffold/scaffold_generator"

class ActiveJob::Notificare::ScaffoldGeneratorTest < Rails::Generators::TestCase
  tests ActiveJob::Notificare::Generators::ScaffoldGenerator
  destination Rails.root.join("tmp/generator_test")
  setup :prepare_destination

  # --- File generation (ScaffoldDemoJob exists and includes the concern) ---

  test "generates controller file" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_file "app/controllers/scaffold_demos_controller.rb" do |content|
      assert_match "class ScaffoldDemosController < ApplicationController", content
      assert_match "ScaffoldDemoJob", content
      assert_match "ActiveJob::Notificare::Execution", content
      assert_match "ActiveJob::Notificare::Notification", content
      assert_match "current_recipient", content
    end
  end

  test "generates index view with i18n t() calls and no hardcoded English" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_file "app/views/scaffold_demos/index.html.erb" do |content|
      assert_match "active_job_notificare", content
      assert_match "active_job_notifications", content
      assert_match "turbo_stream_from", content
      assert_match "scaffold_demo_path(execution)", content
      # locale keys present
      assert_match 't(".title")', content
      assert_match 't(".empty")', content
      assert_match 't(".details")', content
      assert_match 't(".status_label")', content
      assert_match 't(".started_label")', content
      # no bare English strings
      assert_no_match "Details", content
      assert_no_match "No scaffold", content
    end
  end

  test "generates show view with i18n t() calls and no hardcoded English" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_file "app/views/scaffold_demos/show.html.erb" do |content|
      assert_match "active_job_notificare", content
      assert_match "turbo_stream_from", content
      assert_match "scaffold_demos_path", content
      assert_match "@notifications", content
      # locale keys present
      assert_match 't(".title")', content
      assert_match 't(".back")', content
      assert_match 't(".status_label")', content
      assert_match 't(".progress_heading")', content
      assert_match 't(".notifications_heading")', content
      assert_match 't(".no_notifications")', content
      # no bare English heading strings
      assert_no_match '"Progress"', content
      assert_no_match '"Notifications"', content
    end
  end

  test "generates locale file with all expected keys" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_file "config/locales/active_job_notificare_scaffold_demos.en.yml" do |content|
      assert_match "scaffold_demos:", content
      assert_match "title:", content
      assert_match "empty:", content
      assert_match "details:", content
      assert_match "status_label:", content
      assert_match "started_label:", content
      assert_match "back:", content
      assert_match "progress_heading:", content
      assert_match "notifications_heading:", content
      assert_match "no_notifications:", content
    end
  end

  test "locale file uses the prefix as the top-level i18n key" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_file "config/locales/active_job_notificare_scaffold_demos.en.yml" do |content|
      assert_match "scaffold_demos:", content
    end
  end

  test "prints routes snippet to stdout" do
    output = run_generator [ "ScaffoldDemoJob" ]
    assert_match "resources :scaffold_demos, only: [:index, :show]", output
  end

  test "does not modify config/routes.rb" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_no_file "config/routes.rb"
  end

  # --- Naming convention ---

  test "derives controller, views, and locale file from job class name" do
    run_generator [ "ScaffoldDemoJob" ]
    assert_file "app/controllers/scaffold_demos_controller.rb"
    assert_file "app/views/scaffold_demos/index.html.erb"
    assert_file "app/views/scaffold_demos/show.html.erb"
    assert_file "config/locales/active_job_notificare_scaffold_demos.en.yml"
  end

  # --- Override flags ---

  test "--controller flag overrides controller class name" do
    run_generator [ "ScaffoldDemoJob", "--controller=DemoRunsController" ]
    assert_file "app/controllers/scaffold_demos_controller.rb" do |content|
      assert_match "class DemoRunsController < ApplicationController", content
    end
  end

  test "--prefix flag overrides route, view directory, and locale file name" do
    run_generator [ "ScaffoldDemoJob", "--prefix=demo_runs" ]
    assert_file "app/controllers/demo_runs_controller.rb"
    assert_file "app/views/demo_runs/index.html.erb"
    assert_file "app/views/demo_runs/show.html.erb"
    assert_file "config/locales/active_job_notificare_demo_runs.en.yml" do |content|
      assert_match "demo_runs:", content
    end
  end

  test "--prefix flag is reflected in routes snippet" do
    output = run_generator [ "ScaffoldDemoJob", "--prefix=demo_runs" ]
    assert_match "resources :demo_runs, only: [:index, :show]", output
  end

  test "--controller and --prefix flags are independent" do
    run_generator [ "ScaffoldDemoJob", "--controller=CustomController", "--prefix=custom_prefix" ]
    assert_file "app/controllers/custom_prefix_controller.rb" do |content|
      assert_match "class CustomController < ApplicationController", content
    end
    assert_file "app/views/custom_prefix/index.html.erb"
    assert_file "config/locales/active_job_notificare_custom_prefix.en.yml"
  end

  # --- Validation ---

  test "prints error and skips files when job class does not include ActiveJob::Notificare" do
    # String is a real class but does not include the concern
    output = run_generator [ "String" ]
    assert_match "String", output
    assert_match "ActiveJob::Notificare", output
    assert_no_file "app/controllers/strings_controller.rb"
    assert_no_file "app/views/strings/index.html.erb"
    assert_no_file "config/locales/active_job_notificare_strings.en.yml"
  end

  test "does not print routes snippet when class is missing the concern" do
    output = run_generator [ "String" ]
    assert_no_match "resources :strings", output
  end

  test "prints error and skips files when job class cannot be loaded" do
    output = run_generator [ "NonExistentJobAbc123" ]
    assert_match "NonExistentJobAbc123", output
    assert_no_file "app/controllers/non_existent_job_abc123s_controller.rb"
    assert_no_file "config/locales/active_job_notificare_non_existent_job_abc123s.en.yml"
  end
end
