module ActiveJob
  module Notificare
    module ViewHelpers
      def active_job_notificare(execution)
        render partial: "active_job/notificare/progress", locals: { execution: execution }
      end

      def active_job_notifications(for: nil)
        recipient = binding.local_variable_get(:for)
        notifications = Notification.where(recipient: recipient).visible
        render partial: "active_job/notificare/notifications", locals: { notifications: notifications, recipient: recipient }
      end

      # In engine context (engine's own controller views or tests with engine routes included),
      # the bare route helpers like read_notification_path are defined on self.
      # In host app views they are not, so we fall back to url_for with the full controller
      # path, which the host app's route set resolves to the correct mounted prefix.
      def notificare_read_notification_path(notification)
        if respond_to?(:read_notification_path)
          read_notification_path(notification)
        else
          url_for(controller: "active_job/notificare/notifications", action: "read", id: notification.to_param, only_path: true)
        end
      end

      def notificare_dismiss_notification_path(notification)
        if respond_to?(:dismiss_notification_path)
          dismiss_notification_path(notification)
        else
          url_for(controller: "active_job/notificare/notifications", action: "dismiss", id: notification.to_param, only_path: true)
        end
      end

      def notificare_clear_notifications_path
        if respond_to?(:clear_notifications_path)
          clear_notifications_path
        else
          url_for(controller: "active_job/notificare/notifications", action: "clear", only_path: true)
        end
      end
    end
  end
end
