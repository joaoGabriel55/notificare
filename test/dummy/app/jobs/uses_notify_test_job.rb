class UsesNotifyTestJob < ApplicationJob
  include ActiveJob::Notificare
  uses_notify!

  def perform(recipient:)
    self.recipient = recipient
    notify(title: "job done")
  end
end
