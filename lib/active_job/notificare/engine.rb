require "active_job/notificare/projection"

module ActiveJob
  module Notificare
    class Engine < ::Rails::Engine
      isolate_namespace ActiveJob::Notificare

      initializer "active_job.notificare.projection" do
        ActiveJob::Notificare::Projection.subscribe!
      end

      initializer "active_job.notificare.helpers" do
        ActiveSupport.on_load(:action_view) do
          include ActiveJob::Notificare::ViewHelpers
        end
      end

      config.to_prepare do
        unless ::Notificare.const_defined?(:Execution, false)
          ::Notificare.const_set(:Execution, ActiveJob::Notificare::Execution)
        end
        unless ::Notificare.const_defined?(:Notification, false)
          ::Notificare.const_set(:Notification, ActiveJob::Notificare::Notification)
        end
      end
    end
  end
end
