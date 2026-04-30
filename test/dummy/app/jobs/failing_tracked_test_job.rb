class FailingTrackedTestJob < ApplicationJob
  def self.tracks_progress? = true

  def perform
    raise StandardError, "something went wrong"
  end
end
