class ManualNotifyTestJob < ApplicationJob
  include ActiveJob::Notificare
  notify_on :completed

  def perform(recipient:)
    self.recipient = recipient
    notify(
      title: "halfway done",
      description: "midpoint reached",
      metadata: { step: 1 },
      actions: ["view", "dismiss"]
    )
  end
end
