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

        # Step completed without interruption. If StepDSL stashed a `notify:` value for this
        # step, log it for now — actual Notification row write lands in ticket 06.
        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("step_completed.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          step = event.payload[:step]
          notify_event = job.respond_to?(:notificare_step_notify_for) ? job.notificare_step_notify_for(step.name) : nil
          if notify_event
            Rails.logger.debug do
              "[notificare] step_completed step=#{step.name} would-write notification event=#{notify_event.inspect}"
            end
          end
        end

        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("perform.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          execution = Execution.find_by(job_id: job.job_id)
          next unless execution

          if (exception = event.payload[:exception_object])
            execution.update!(status: "failed", completed_at: Time.current, error: exception.message)
          else
            execution.update!(status: "completed", completed_at: Time.current)
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
    end
  end
end
