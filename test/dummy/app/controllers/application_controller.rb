class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :current_user

  def current_notificare_recipient
    User.find_by(id: session[:user_id])
  end

  private

  def current_user
    @current_user ||= User.first || User.create!(name: "Demo User")
  end
end
