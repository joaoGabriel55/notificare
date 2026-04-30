require "active_support/concern"
require "active_job/continuation"
require "active_job/continuable"

module ActiveJob
  module Notificare
    extend ActiveSupport::Concern

    included do
      include ActiveJob::Continuable
      include StepDSL
    end

    class_methods do
      # Opt out of the projection. Including the module is the opt-in;
      # `tracks_progress false` flips it off without removing the include.
      def tracks_progress(value = true)
        @tracks_progress = value
      end

      def tracks_progress?
        @tracks_progress != false
      end

      # Declare which lifecycle events auto-write a Notification row.
      # Accepted values: :completed, :failed (or both).
      def notify_on(*event_types)
        @_notificare_notify_on = event_types.map(&:to_sym)
      end

      def notificare_notify_on
        @_notificare_notify_on || []
      end
    end

    # The polymorphic recipient for notifications. Job authors set this inside
    # perform (e.g. `self.recipient = recipient`). Enforcement that it is
    # present at enqueue time lands in ticket 07.
    attr_accessor :recipient

    def progress
      @progress ||= ProgressHandle.new(job_id)
    end
  end
end
