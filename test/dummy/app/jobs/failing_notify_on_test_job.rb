class FailingNotifyOnTestJob < ApplicationJob
  include ActiveJob::Notificare
  notify_on :completed, :failed

  def perform(recipient:)
    self.recipient = recipient
    raise StandardError, "notify_on failure"
  end
end
