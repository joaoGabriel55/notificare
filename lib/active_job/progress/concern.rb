require "active_support/concern"

module ActiveJob
  module Progress
    extend ActiveSupport::Concern

    class_methods do
      def tracks_progress
        @tracks_progress = true
      end

      def tracks_progress?
        @tracks_progress == true
      end
    end

    def progress
      @progress ||= ProgressHandle.new(job_id)
    end
  end
end
