module ActiveJob
  module Notificare
    class NotificationsController < ApplicationController
      before_action :set_current_recipient
      before_action :set_notification, only: [ :read, :dismiss ]

      def read
        @notification.mark_read!
        head :ok
      end

      def dismiss
        @notification.dismiss!
        head :ok
      end

      def clear
        Notification.where(recipient: @current_recipient).visible.destroy_all
        head :ok
      end

      private

      def set_current_recipient
        @current_recipient = resolve_current_recipient
        head :unauthorized if @current_recipient.nil?
      end

      def resolve_current_recipient
        if (proc = ActiveJob::Notificare.current_recipient_proc)
          instance_exec(&proc)
        elsif respond_to?(:current_user, true)
          send(:current_user)
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
