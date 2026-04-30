class StepNotifyTestJob < ApplicationJob
  include ActiveJob::Notificare

  cattr_accessor :ran_steps, default: []

  def perform(recipient:)
    self.recipient = recipient
    self.class.ran_steps = []

    step(:validate, notify: :validated) do
      self.class.ran_steps << :validate
    end

    step(:process, notify: { event: :processed, title: "Processing complete", description: "rows done", metadata: { count: 42 } }) do
      self.class.ran_steps << :process
    end

    step(:finalize) do
      self.class.ran_steps << :finalize
    end
  end
end
