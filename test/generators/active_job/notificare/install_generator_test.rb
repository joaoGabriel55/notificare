require "test_helper"
require "generators/active_job/notificare/install/install_generator"
require "rails/generators/test_case"

class ActiveJob::Notificare::Generators::InstallGeneratorTest < Rails::Generators::TestCase
  tests ActiveJob::Notificare::Generators::InstallGenerator
  destination File.expand_path("../../../tmp/install_generator", __dir__)
  setup :prepare_destination

  setup do
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), <<~RUBY)
      Rails.application.routes.draw do
      end
    RUBY
  end

  private

  def with_adapter_name(name)
    conn = ActiveRecord::Base.connection
    conn.define_singleton_method(:adapter_name) { name }
    yield
  ensure
    conn.singleton_class.remove_method(:adapter_name)
  end

  public

  test "creates migration with both tables" do
    run_generator
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/create_table :active_job_executions/, content)
      assert_match(/create_table :active_job_notifications/, content)
    end
  end

  test "migration includes all executions columns" do
    run_generator
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/t\.string :job_id,.*null: false/, content)
      assert_match(/t\.string :job_class,.*null: false/, content)
      assert_match(/t\.string :status/, content)
      assert_match(/t\.string :current_step/, content)
      assert_match(/t\.integer :progress_current/, content)
      assert_match(/t\.integer :progress_total/, content)
      assert_match(/t\.datetime :started_at/, content)
      assert_match(/t\.datetime :completed_at/, content)
      assert_match(/t\.text :error/, content)
      assert_match(/t\.timestamps/, content)
    end
  end

  test "migration includes all notifications columns" do
    run_generator
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/t\.string :recipient_type,.*null: false/, content)
      assert_match(/t\.string :recipient_id,.*null: false/, content)
      assert_match(/t\.string :job_id/, content)
      assert_match(/t\.string :event_type,.*null: false/, content)
      assert_match(/t\.string :title,.*null: false/, content)
      assert_match(/t\.text :description/, content)
      assert_match(/t\.\w+ :metadata/, content)
      assert_match(/t\.\w+ :actions/, content)
      assert_match(/t\.datetime :read_at/, content)
      assert_match(/t\.datetime :dismissed_at/, content)
    end
  end

  test "migration includes correct indexes" do
    run_generator
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/add_index :active_job_executions, :job_id, unique: true/, content)
      assert_match(/add_index :active_job_executions, :job_class/, content)
      assert_match(/add_index :active_job_notifications, :recipient_id/, content)
      assert_match(/add_index :active_job_notifications, :job_id/, content)
    end
  end

  test "migration uses text type for SQLite adapter" do
    run_generator
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/t\.text :metadata/, content)
      assert_match(/t\.text :actions/, content)
    end
  end

  test "migration uses jsonb type for PostgreSQL adapter" do
    with_adapter_name("PostgreSQL") { run_generator }
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/t\.jsonb :metadata/, content)
      assert_match(/t\.jsonb :actions/, content)
    end
  end

  test "migration uses json type for MySQL adapter" do
    with_adapter_name("Mysql2") { run_generator }
    assert_migration "db/migrate/create_active_job_notificare_tables.rb" do |content|
      assert_match(/t\.json :metadata/, content)
      assert_match(/t\.json :actions/, content)
    end
  end

  test "creates initializer" do
    run_generator
    assert_file "config/initializers/active_job_notificare.rb",
      /ActiveJob::Notificare.configure/,
      /execution_retention/,
      /broadcast_progress/,
      /broadcast_notifications/
  end

  test "appends route comment to routes.rb" do
    run_generator
    assert_file "config/routes.rb", /ActiveJob::Notificare::Engine/
  end

  test "creates progress partial stub" do
    run_generator
    assert_file "app/views/active_job/notificare/_progress.html.erb"
  end

  test "creates notifications partial stub" do
    run_generator
    assert_file "app/views/active_job/notificare/_notifications.html.erb"
  end

  test "running generator twice does not duplicate migration" do
    run_generator
    @generator = nil  # force a fresh generator instance for second invocation
    run_generator     # identical template output — name guard silently skips
    migrations = Dir.glob(File.join(destination_root, "db/migrate/*_create_active_job_notificare_tables.rb"))
    assert_equal 1, migrations.size
  end
end
