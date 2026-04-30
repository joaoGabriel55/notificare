module ActiveJob
  module Notificare
    class ApplicationRecord < ::ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
