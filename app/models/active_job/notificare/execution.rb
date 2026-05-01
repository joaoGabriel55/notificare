module ActiveJob
  module Notificare
    class Execution < ApplicationRecord
      self.table_name = "active_job_executions"

      if defined?(Turbo::Broadcastable)
        include Turbo::Broadcastable
        broadcasts_refreshes_to ->(execution) { [ "active_job_progress", execution.job_id ] }
      end

      enum :status, { enqueued: "enqueued", running: "running", completed: "completed", failed: "failed" }

      scope :recent, -> { order(created_at: :desc) }

      validates :job_id, presence: true, uniqueness: true
      validates :job_class, presence: true
      validates :status, presence: true
    end
  end
end
