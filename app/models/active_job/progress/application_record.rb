module ActiveJob
  module Progress
    class ApplicationRecord < ::ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
