class HomeController < ApplicationController
  def index
    @user = User.find(params[:user_id])
    @execution = params[:job_id] ? ActiveJob::Notificare::Execution.find_by(job_id: params[:job_id]) : nil
  end
end
