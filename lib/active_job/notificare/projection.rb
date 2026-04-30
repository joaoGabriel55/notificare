module ActiveJob
  module Notificare
    module Projection
      SUBSCRIPTIONS = []

      def self.subscribe!
        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("enqueue.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          begin
            Execution.find_or_create_by!(job_id: job.job_id) do |e|
              e.job_class = job.class.name
              e.status = "enqueued"
            end
          rescue ActiveRecord::RecordNotUnique
            # Two concurrent projections for the same job_id — uniqueness constraint caught the
            # duplicate; the other thread won, so just find the existing row.
            Execution.find_by!(job_id: job.job_id)
          end
        end

        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("perform_start.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          execution = Execution.find_by(job_id: job.job_id)
          next unless execution

          if execution.running?
            # Resume path (ERD §9 case 3): worker was killed before perform.active_job fired,
            # leaving status as running. Preserve progress_current and started_at.
            # No continuation_state column — Continuation owns that (ERD §6).
            execution.update!(error: nil) if execution.error.present?
          else
            execution.update!(status: "running", started_at: Time.current)
          end
        end

        # Mirror ActiveJob::Continuation's current step name onto the execution row.
        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("step_started.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          step = event.payload[:step]
          Execution.find_by(job_id: job.job_id)&.update!(current_step: step.name.to_s)
        end

        # ActiveJob::Continuation fires `step.active_job` (not `step_completed`) after each step's
        # block finishes (whether successfully or with an exception). Only write a notification
        # when the step completed without error and was not interrupted.
        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("step.active_job") do |event|
          next if event.payload[:exception_object]
          next if event.payload[:interrupted]

          job = event.payload[:job]
          next unless tracks_progress?(job)

          step = event.payload[:step]
          notify_event = job.respond_to?(:notificare_step_notify_for) ? job.notificare_step_notify_for(step.name) : nil
          write_step_notification(job, step.name, notify_event) if notify_event
        end

        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("perform.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          execution = Execution.find_by(job_id: job.job_id)
          next unless execution

          if (exception = event.payload[:exception_object])
            execution.update!(status: "failed", completed_at: Time.current, error: exception.message)
            write_lifecycle_notification(job, :failed, exception.message) if notifies_on?(job, :failed)
          else
            execution.update!(status: "completed", completed_at: Time.current)
            write_lifecycle_notification(job, :completed) if notifies_on?(job, :completed)
          end
        end
      end

      def self.unsubscribe!
        SUBSCRIPTIONS.each { |s| ActiveSupport::Notifications.unsubscribe(s) }
        SUBSCRIPTIONS.clear
      end

      def self.tracks_progress?(job)
        job.class.respond_to?(:tracks_progress?) && job.class.tracks_progress?
      end
      private_class_method :tracks_progress?

      def self.notifies_on?(job, event_type)
        job.class.respond_to?(:notificare_notify_on) && job.class.notificare_notify_on.include?(event_type)
      end
      private_class_method :notifies_on?

      def self.recipient_for(job)
        job.respond_to?(:recipient) ? job.recipient : nil
      end
      private_class_method :recipient_for

      def self.write_lifecycle_notification(job, event_type, description = nil)
        recipient = recipient_for(job)
        return unless recipient

        Notification.create!(
          recipient: recipient,
          job_id: job.job_id,
          event_type: event_type.to_s,
          title: "#{job.class.name} #{event_type}",
          description: description
        )
      end
      private_class_method :write_lifecycle_notification

      def self.write_step_notification(job, step_name, notify_event)
        recipient = recipient_for(job)
        return unless recipient

        Notification.create!(build_step_notification_attrs(job, step_name, notify_event))
      end
      private_class_method :write_step_notification

      def self.build_step_notification_attrs(job, step_name, notify_event)
        base = { recipient: recipient_for(job), job_id: job.job_id, event_type: "custom" }

        case notify_event
        when Symbol
          base.merge(
            title: "#{job.class.name}: #{notify_event}",
            metadata: { "event" => notify_event.to_s }
          )
        when Hash
          event = notify_event[:event] || step_name
          extra_metadata = notify_event[:metadata]&.transform_keys(&:to_s) || {}
          base.merge(
            title: notify_event[:title] || "#{job.class.name}: #{event}",
            description: notify_event[:description],
            metadata: { "event" => event.to_s }.merge(extra_metadata)
          )
        end
      end
      private_class_method :build_step_notification_attrs
    end
  end
end
