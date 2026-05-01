module ActiveJob
  module Notificare
    class NotificationsController < ApplicationController
      before_action :set_current_recipient
      before_action :set_notification, only: [ :read, :dismiss ]

      def read
        @notification.mark_read!
        respond_to do |format|
          format.turbo_stream
          format.html { head :ok }
        end
      end

      def dismiss
        @notification.dismiss!
        respond_to do |format|
          format.turbo_stream
          format.html { head :ok }
        end
      end

      def clear
        @notifications = Notification.where(recipient: @current_recipient).visible.to_a
        Notification.where(id: @notifications.map(&:id)).destroy_all
        respond_to do |format|
          format.turbo_stream
          format.html { head :ok }
        end
      end

      private

      def set_current_recipient
        @current_recipient = resolve_current_recipient
        head :unauthorized if @current_recipient.nil?
      end

      def resolve_current_recipient
        if (proc = ActiveJob::Notificare.current_recipient_proc)
          instance_exec(&proc)
        elsif respond_to?(:current_notificare_recipient, true)
          current_notificare_recipient
        elsif respond_to?(:current_user, true)
          current_user
        else
          raise NotImplementedError, <<~MSG
            Could not resolve the current recipient for ActiveJob::Notificare.

            To fix this, do one of the following:

            1. Override `current_notificare_recipient` in your ApplicationController:

                 def current_notificare_recipient
                   current_user  # or however you expose the signed-in user
                 end

            2. Set a proc in an initializer:

                 ActiveJob::Notificare.current_recipient_proc = -> { current_user }
          MSG
        end
      end

      def set_notification
        @notification = Notification.where(recipient: @current_recipient).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end
    end
  end
end
