module ActiveJob
  module Notificare
    class ApplicationController < ActiveJob::Notificare.parent_controller.constantize
      protect_from_forgery with: :exception
    end
  end
end
