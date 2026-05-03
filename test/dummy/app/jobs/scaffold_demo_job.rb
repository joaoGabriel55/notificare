class ScaffoldDemoJob < ApplicationJob
  include ActiveJob::Notificare

  notify_on :completed, :failed

  def perform(recipient:)
    self.recipient = recipient

    step(:process, notify: :processed) do
      # no-op: stand-in for real work
    end
  end
end
