class ProgressDslTestJob < ApplicationJob
  include ActiveJob::Progress
  tracks_progress

  def perform
    progress.total(10)
    10.times { progress.advance! }
  end
end
