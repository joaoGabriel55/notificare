require "active_support/concern"

module ActiveJob
  module Notificare
    # around_enqueue guard: raises ArgumentError before the adapter receives the job
    # when the job opts into notifications but no `recipient:` keyword was supplied.
    #
    # Opt-in triggers (any one is sufficient):
    #   - notify_on declared on the class
    #   - uses_notify! called on the class (or uses_notify? already true from a prior run)
    #   - step(notify:) was called in a prior run (has_step_notifications? is true)
    module Recipient
      extend ActiveSupport::Concern

      included do
        around_enqueue :enforce_recipient!
      end

      private

      def enforce_recipient!
        if needs_recipient? && !recipient_argument_present?
          raise ArgumentError, "#{self.class.name} requires a `recipient:` keyword argument"
        end
        yield
      end

      def needs_recipient?
        self.class.notificare_notify_on.any? ||
          self.class.uses_notify? ||
          self.class.has_step_notifications?
      end

      def recipient_argument_present?
        arguments.any? { |arg| arg.is_a?(Hash) && (arg.key?(:recipient) || arg.key?("recipient")) }
      end
    end
  end
end
