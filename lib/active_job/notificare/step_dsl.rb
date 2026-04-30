require "active_support/concern"

module ActiveJob
  module Notificare
    # Wraps ActiveJob::Continuation#step with Notificare-specific kwargs.
    #
    # `notify:` declares a state-machine event tied to the step's successful completion.
    # The value is stashed on the job instance keyed by step name; the projection reads it
    # off `event.payload[:job]` at `step_completed.active_job` time. Actual Notification
    # row writes land in ticket 06.
    module StepDSL
      extend ActiveSupport::Concern

      def step(name, *args, notify: nil, **opts, &block)
        if notify
          @_notificare_step_notify ||= {}
          @_notificare_step_notify[name.to_sym] = notify
        end
        super(name, *args, **opts, &block)
      end

      # Read by Projection's `step_completed.active_job` handler.
      def notificare_step_notify_for(step_name)
        return nil unless defined?(@_notificare_step_notify) && @_notificare_step_notify
        @_notificare_step_notify[step_name.to_sym]
      end
    end
  end
end
