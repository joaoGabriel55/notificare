class CsvImport < ApplicationRecord
  belongs_to :user

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :filename, :csv_content, presence: true
end
