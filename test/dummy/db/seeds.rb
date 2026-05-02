# Seeds for local development exploration of notificare.
# Run: bin/rails db:seed (from test/dummy/)
# Then visit: http://localhost:3000/home?user_id=1

alice = User.find_or_create_by!(name: "Alice")
bob   = User.find_or_create_by!(name: "Bob")

# -- Executions -----------------------------------------------------------

completed_job_id = SecureRandom.uuid
running_job_id   = SecureRandom.uuid
failed_job_id    = SecureRandom.uuid
enqueued_job_id  = SecureRandom.uuid

ActiveJob::Notificare::Execution.find_or_create_by!(job_id: completed_job_id) do |e|
  e.job_class        = "ImportJob"
  e.status           = "completed"
  e.current_step     = "finalize"
  e.progress_current = 250
  e.progress_total   = 250
  e.started_at       = 10.minutes.ago
  e.completed_at     = 5.minutes.ago
end

ActiveJob::Notificare::Execution.find_or_create_by!(job_id: running_job_id) do |e|
  e.job_class        = "ExportJob"
  e.status           = "running"
  e.current_step     = "process_rows"
  e.progress_current = 120
  e.progress_total   = 300
  e.started_at       = 2.minutes.ago
end

ActiveJob::Notificare::Execution.find_or_create_by!(job_id: failed_job_id) do |e|
  e.job_class    = "SyncJob"
  e.status       = "failed"
  e.current_step = "validate"
  e.error        = "ActiveRecord::RecordInvalid: Validation failed: Email is invalid"
  e.started_at   = 30.minutes.ago
  e.completed_at = 28.minutes.ago
end

ActiveJob::Notificare::Execution.find_or_create_by!(job_id: enqueued_job_id) do |e|
  e.job_class = "ReportJob"
  e.status    = "enqueued"
end

# -- Notifications for Alice ----------------------------------------------

[
  {
    job_id:     completed_job_id,
    event_type: "completed",
    title:      "ImportJob completed",
    description: nil,
    read_at:    nil,
    dismissed_at: nil
  },
  {
    job_id:     failed_job_id,
    event_type: "failed",
    title:      "SyncJob failed",
    description: "ActiveRecord::RecordInvalid: Validation failed: Email is invalid",
    read_at:    nil,
    dismissed_at: nil
  },
  {
    job_id:     completed_job_id,
    event_type: "custom",
    title:      "ImportJob: validated",
    description: nil,
    metadata:   { "event" => "validated" },
    read_at:    20.minutes.ago,
    dismissed_at: nil
  },
  {
    job_id:     completed_job_id,
    event_type: "custom",
    title:      "Processing complete",
    description: "250 rows imported successfully",
    metadata:   { "event" => "processed", "count" => 250 },
    actions:    [ { "label" => "View results", "url" => "/imports/1" } ],
    read_at:    nil,
    dismissed_at: nil
  }
].each do |attrs|
  ActiveJob::Notificare::Notification.find_or_create_by!(
    recipient: alice,
    job_id:    attrs[:job_id],
    event_type: attrs[:event_type],
    title:     attrs[:title]
  ) do |n|
    n.description  = attrs[:description]
    n.metadata     = attrs[:metadata]
    n.actions      = attrs[:actions]
    n.read_at      = attrs[:read_at]
    n.dismissed_at = attrs[:dismissed_at]
  end
end

# -- Notifications for Bob ------------------------------------------------

ActiveJob::Notificare::Notification.find_or_create_by!(
  recipient: bob,
  job_id:    enqueued_job_id,
  event_type: "completed",
  title:      "ReportJob completed"
)

puts "Seeded users: alice (id=#{alice.id}), bob (id=#{bob.id})"
puts ""
puts "Inbox (per-user notifications):"
puts "  http://localhost:3000/home?user_id=#{alice.id}  (Alice)"
puts "  http://localhost:3000/home?user_id=#{bob.id}  (Bob)"
puts ""
puts "Admin UI (all executions):"
puts "  http://localhost:3000/notificare"
