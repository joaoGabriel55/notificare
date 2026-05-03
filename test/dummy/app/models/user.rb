class User < ApplicationRecord
  has_many :csv_imports
end
