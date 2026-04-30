class StepDslTestJob < ApplicationJob
  include ActiveJob::Notificare

  cattr_accessor :ran_steps, default: []

  def perform
    self.class.ran_steps = []
    step(:validate, notify: :validated) do
      self.class.ran_steps << :validate
    end
    step(:finalize) do
      self.class.ran_steps << :finalize
    end
  end
end
