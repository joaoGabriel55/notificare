module ActiveJob
  module Notificare
    class Notification < ApplicationRecord
      self.table_name = "active_job_notifications"

      belongs_to :recipient, polymorphic: true

      enum :event_type, { completed: "completed", failed: "failed", custom: "custom" }

      attribute :metadata, :json, default: nil
      attribute :actions, :json, default: nil

      default_scope { order(created_at: :desc) }

      scope :unread, -> { where(read_at: nil) }
      scope :visible, -> { where(dismissed_at: nil) }

      validates :event_type, presence: true
      validates :title, presence: true

      def read?
        read_at.present?
      end

      def dismissed?
        dismissed_at.present?
      end

      def mark_read!
        update!(read_at: Time.current) unless read?
      end

      def dismiss!
        update!(dismissed_at: Time.current) unless dismissed?
      end
    end
  end
end
