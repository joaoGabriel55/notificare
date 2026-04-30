class FailingStepNotifyTestJob < ApplicationJob
  include ActiveJob::Notificare

  def perform(recipient:)
    self.recipient = recipient

    step(:ok_step, notify: :ok_done) do
      # succeeds
    end

    step(:boom_step, notify: :boom_done) do
      raise StandardError, "step failed"
    end
  end
end
