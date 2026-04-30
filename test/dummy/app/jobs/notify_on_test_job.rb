class NotifyOnTestJob < ApplicationJob
  include ActiveJob::Notificare
  notify_on :completed, :failed

  def perform(recipient:)
    self.recipient = recipient
  end
end
