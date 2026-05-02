class ScaffoldDemosController < ApplicationController
  def index
    job_ids = ActiveJob::Notificare::Notification
      .where(recipient: current_recipient)
      .select(:job_id)
      .distinct
    @executions = ActiveJob::Notificare::Execution
      .where(job_class: "ScaffoldDemoJob", job_id: job_ids)
      .recent
  end

  def show
    @execution = ActiveJob::Notificare::Execution
      .where(job_class: "ScaffoldDemoJob")
      .find(params[:id])
    @notifications = ActiveJob::Notificare::Notification
      .where(recipient: current_recipient, job_id: @execution.job_id)
      .visible
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def current_recipient
    current_notificare_recipient || current_user
  end
  helper_method :current_recipient
end
