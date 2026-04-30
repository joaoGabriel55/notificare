require "test_helper"

class ActiveJobNotificareSchemaTest < ActiveSupport::TestCase
  def connection
    ActiveRecord::Base.connection
  end

  # active_job_executions

  test "active_job_executions table exists" do
    assert connection.table_exists?(:active_job_executions)
  end

  test "active_job_executions has all documented columns" do
    columns = connection.columns(:active_job_executions).map(&:name)
    %w[
      id job_id job_class status current_step
      progress_current progress_total
      started_at completed_at error
      created_at updated_at
    ].each do |col|
      assert_includes columns, col
    end
  end

  test "active_job_executions job_id index is unique" do
    indexes = connection.indexes(:active_job_executions)
    job_id_index = indexes.find { |i| i.columns == [ "job_id" ] }
    assert job_id_index, "missing index on job_id"
    assert job_id_index.unique, "job_id index must be unique"
  end

  test "active_job_executions job_class index exists" do
    index_columns = connection.indexes(:active_job_executions).map(&:columns)
    assert_includes index_columns, [ "job_class" ]
  end

  # active_job_notifications

  test "active_job_notifications table exists" do
    assert connection.table_exists?(:active_job_notifications)
  end

  test "active_job_notifications has all documented columns" do
    columns = connection.columns(:active_job_notifications).map(&:name)
    %w[
      id recipient_type recipient_id job_id
      event_type title description
      metadata actions
      read_at dismissed_at
      created_at updated_at
    ].each do |col|
      assert_includes columns, col
    end
  end

  test "active_job_notifications recipient_id index exists" do
    index_columns = connection.indexes(:active_job_notifications).map(&:columns)
    assert_includes index_columns, [ "recipient_id" ]
  end

  test "active_job_notifications job_id index exists" do
    index_columns = connection.indexes(:active_job_notifications).map(&:columns)
    assert_includes index_columns, [ "job_id" ]
  end
end
