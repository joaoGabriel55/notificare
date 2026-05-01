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
    end
  end
end
