require "active_job/notificare/version"
require "active_job/notificare/engine"
require "active_job/notificare/progress_handle"
require "active_job/notificare/step_dsl"
require "active_job/notificare/recipient"
require "active_job/notificare/concern"

module ActiveJob
  module Notificare
    mattr_accessor :current_recipient_proc
    mattr_accessor :parent_controller, default: "ApplicationController"
  end
end
