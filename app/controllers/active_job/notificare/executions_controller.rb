module ActiveJob
  module Notificare
    class ExecutionsController < ApplicationController
      PER_PAGE = 25

      before_action :authenticate_notificare!

      def index
        scope = Execution.recent
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(job_class: params[:job_class]) if params[:job_class].present?

        @page = [ params.fetch(:page, 1).to_i, 1 ].max
        @total_count = scope.count
        @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
        @page = [ @page, @total_pages ].min
        @executions = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
        @statuses = Execution.statuses.keys
        @job_classes = Execution.distinct.pluck(:job_class).sort
      end

      def show
        @execution = Execution.find(params[:id])
        @notifications = Notification.where(job_id: @execution.job_id).limit(50)
      rescue ActiveRecord::RecordNotFound
        head :not_found
      end

      private

      def authenticate_notificare!
        proc = ActiveJob::Notificare.authenticate_with
        if proc.nil?
          head :forbidden if Rails.env.production?
        elsif !instance_exec(&proc)
          head :forbidden
        end
      end
    end
  end
end
