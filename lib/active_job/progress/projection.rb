module ActiveJob
  module Progress
    module Projection
      SUBSCRIPTIONS = []

      def self.subscribe!
        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("enqueue.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          Execution.find_or_create_by!(job_id: job.job_id) do |e|
            e.job_class = job.class.name
            e.status = "enqueued"
          end
        end

        SUBSCRIPTIONS << ActiveSupport::Notifications.subscribe("perform_start.active_job") do |event|
          job = event.payload[:job]
          next unless tracks_progress?(job)

          Execution.find_by(job_id: job.job_id)&.update!(
            status: "running",
            started_at: Time.current
          )
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
