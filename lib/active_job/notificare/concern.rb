require "active_support/concern"
require "active_job/continuation"
require "active_job/continuable"

module ActiveJob
  module Notificare
    extend ActiveSupport::Concern

    included do
      include ActiveJob::Continuable
      include StepDSL
      include Recipient
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

      # Eagerly opt into recipient enforcement at enqueue time, before any instance
      # has called notify(...). Use this when you know the job will call notify but
      # want the ArgumentError to fire on the very first enqueue.
      def uses_notify!
        @_uses_notify = true
      end

      # True if uses_notify! was called explicitly, or after the first instance called
      # notify(...) during perform (which flips this flag).
      def uses_notify?
        @_uses_notify == true
      end
    end

    # The polymorphic recipient for notifications. Job authors set this inside
    # perform (e.g. `self.recipient = recipient`).
    attr_accessor :recipient

    def progress
      @progress ||= ProgressHandle.new(job_id)
    end

    # Write a custom Notification row directly. Safe to call at any point during or
    # after perform — does not rely on lifecycle hooks (ERD §9 case 5).
    #
    # Also flips self.class.uses_notify? to true so subsequent enqueues are subject
    # to recipient enforcement.
    def notify(title:, description: nil, metadata: {}, actions: [])
      self.class.uses_notify!
      return unless recipient

      Notification.create!(
        recipient: recipient,
        job_id: job_id,
        event_type: "custom",
        title: title,
        description: description,
        metadata: metadata.presence,
        actions: actions.presence
      )
    end
  end
end
