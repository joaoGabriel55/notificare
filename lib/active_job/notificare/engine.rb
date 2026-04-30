require "active_job/notificare/projection"

module ActiveJob
  module Notificare
    class Engine < ::Rails::Engine
      isolate_namespace ActiveJob::Notificare

      initializer "active_job.notificare.projection" do
        ActiveJob::Notificare::Projection.subscribe!
      end

      config.to_prepare do
        unless ::Notificare.const_defined?(:Execution, false)
          ::Notificare.const_set(:Execution, ActiveJob::Notificare::Execution)
        end
      end
    end
  end
end
