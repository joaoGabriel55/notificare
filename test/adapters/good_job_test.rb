require_relative "adapter_test_helper"

# Notificare tables are created in AdapterTestHelper.prepare_database!
# GoodJob tables are created here using GoodJob's own schema migration.
AdapterTestHelper.prepare_database!

# GoodJob's schema uses jsonb (Postgres). If running against SQLite this will
# fail at the ActiveRecord::Schema.define step, which is intentional — these
# tests require Postgres (DATABASE_URL must point to a Postgres instance).
ActiveRecord::Schema.define do
  suppress_messages do
    enable_extension "pgcrypto" rescue nil  # Postgres ≥ 13 has gen_random_uuid built-in
    create_table :good_jobs, id: :uuid, force: :cascade do |t|
      t.text     :queue_name
      t.integer  :priority
      t.jsonb    :serialized_params
      t.datetime :scheduled_at
      t.datetime :performed_at
      t.datetime :finished_at
      t.text     :error
      t.timestamps
      t.uuid     :active_job_id
      t.text     :concurrency_key
      t.text     :cron_key
      t.uuid     :retried_good_job_id
      t.datetime :cron_at
      t.uuid     :batch_id
      t.uuid     :batch_callback_id
      t.boolean  :is_discrete
      t.integer  :executions_count
      t.text     :job_class
      t.integer  :error_event, limit: 2
      t.text     :labels, array: true
      t.uuid     :locked_by_id
      t.datetime :locked_at
      t.integer  :lock_type, limit: 2
    end

    create_table :good_job_batches, id: :uuid, force: :cascade do |t|
      t.timestamps
      t.text     :description
      t.jsonb    :serialized_properties
      t.text     :on_finish
      t.text     :on_success
      t.text     :on_discard
      t.text     :callback_queue_name
      t.integer  :callback_priority
      t.datetime :enqueued_at
      t.datetime :discarded_at
      t.datetime :finished_at
      t.datetime :jobs_finished_at
    end

    create_table :good_job_executions, id: :uuid, force: :cascade do |t|
      t.timestamps
      t.uuid     :active_job_id, null: false
      t.text     :job_class
      t.text     :queue_name
      t.jsonb    :serialized_params
      t.datetime :scheduled_at
      t.datetime :finished_at
      t.text     :error
      t.integer  :error_event, limit: 2
      t.text     :error_backtrace, array: true
      t.uuid     :process_id
      t.interval :duration
    end

    create_table :good_job_processes, id: :uuid, force: :cascade do |t|
      t.timestamps
      t.jsonb    :state
      t.integer  :lock_type, limit: 2
    end

    create_table :good_job_settings, id: :uuid, force: :cascade do |t|
      t.timestamps
      t.text     :key
      t.jsonb    :value
      t.index [ :key ], unique: true
    end
  end
end

class GoodJobAdapterTest < AdapterTestHelper::TestCase
  setup do
    ActiveJob::Base.queue_adapter = :good_job
  end

  teardown do
    ActiveJob::Base.queue_adapter = :test
    GoodJob::Job.delete_all   rescue nil
    GoodJob::Execution.delete_all rescue nil
  end

  # Drain via GoodJob.perform_inline — the documented test-environment drain
  # (documented at https://github.com/bensheldon/good_job).
  def drain_good_job
    GoodJob.perform_inline
  rescue StandardError
    # GoodJob.perform_inline re-raises unhandled errors. The perform.active_job
    # event already fired with exception_object, so the Notificare row is failed.
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  test "enqueues job and creates execution row with enqueued status" do
    job = NotifyOnTestJob.perform_later(recipient: @user)

    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.enqueued?, "expected enqueued status after perform_later"
  end

  test "draining transitions execution to completed" do
    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_good_job
    assert_execution_completed(job.job_id)
  end

  test "completed notification is written after drain" do
    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_good_job
    assert_notification_written(recipient: @user, event_type: "completed")
  end

  test "failed job transitions to failed status" do
    job = FailingTrackedTestJob.perform_later
    drain_good_job
    execution = ActiveJob::Notificare::Execution.find_by!(job_id: job.job_id)
    assert execution.failed?, "expected failed status"
    assert_equal "something went wrong", execution.error
  end

  test "step-level notifications are written for each completed step" do
    job = StepNotifyTestJob.perform_later(recipient: @user)
    drain_good_job
    notifications = ActiveJob::Notificare::Notification.where(recipient: @user, event_type: "custom")
    assert notifications.exists?, "expected at least one custom (step) notification"
  end

  # ---------------------------------------------------------------------------
  # Smoke: AS::Notifications instrumentation fires identically to :test adapter
  # ---------------------------------------------------------------------------

  test "AS::Notifications events fire for GoodJob identically to the test adapter" do
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/\.active_job$/) do |name, *|
      events << name
    end

    job = NotifyOnTestJob.perform_later(recipient: @user)
    drain_good_job

    ActiveSupport::Notifications.unsubscribe(subscriber)

    assert_includes events, "enqueue.active_job"
    assert_includes events, "perform_start.active_job"
    assert_includes events, "perform.active_job"
  end
end
