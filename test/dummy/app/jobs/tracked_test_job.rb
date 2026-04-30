class TrackedTestJob < ApplicationJob
  def self.tracks_progress? = true

  def perform
  end
end
