require "csv"

class CsvImportJob < ApplicationJob
  include ActiveJob::Notificare

  notify_on :completed, :failed

  def perform(csv_import_id:, recipient:)
    self.recipient = recipient
    @import = CsvImport.find(csv_import_id)

    step(:validate_file) do
      first_line = @import.csv_content.lines.first.to_s.strip
      headers = CSV.parse_line(first_line) || []
      required = %w[name email]
      missing = required - headers.map(&:downcase).map(&:strip)
      raise "Missing required columns: #{missing.join(', ')}" if missing.any?

      @import.update!(status: :processing)
    end

    step(:process_rows, notify: { event: :rows_processed, title: "Rows processed", description: "All CSV rows have been imported successfully." }) do
      rows = CSV.parse(@import.csv_content, headers: true)
      progress.total(rows.length)

      rows.each_with_index do |_row, i|
        sleep 0.1
        @import.update!(processed_rows: i + 1)
        progress.advance!
      end
    end

    step(:finalize, notify: { event: :finalized, title: "Import finalized", description: "#{@import.total_rows} contacts are ready." }) do
      @import.update!(status: :completed, completed_at: Time.current)
    end
  end
end
