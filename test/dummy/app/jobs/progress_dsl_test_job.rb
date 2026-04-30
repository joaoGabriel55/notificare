class ProgressDslTestJob < ApplicationJob
  include ActiveJob::Notificare

  def perform
    progress.total(10)
    10.times { progress.advance! }
  end
end
