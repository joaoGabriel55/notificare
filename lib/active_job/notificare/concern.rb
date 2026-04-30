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
    end

    def progress
      @progress ||= ProgressHandle.new(job_id)
    end
  end
end
