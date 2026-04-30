require "active_job/progress/projection"

module ActiveJob
  module Progress
    class Engine < ::Rails::Engine
      isolate_namespace ActiveJob::Progress

      initializer "active_job.progress.projection" do
        ActiveJob::Progress::Projection.subscribe!
      end

      config.to_prepare do
        Koraci.const_set(:Execution, ActiveJob::Progress::Execution)
      end
    end
  end
end
