require "csv"

class CsvImportsController < ApplicationController
  def index
    @csv_imports = current_user.csv_imports.order(created_at: :desc)
  end

  def new
    @csv_import = CsvImport.new
  end

  def create
    uploaded = params.dig(:csv_import, :file)

    unless uploaded.present?
      @csv_import = CsvImport.new
      flash.now[:alert] = "Please select a CSV file."
      return render :new, status: :unprocessable_entity
    end

    content = uploaded.read.force_encoding("UTF-8")
    rows = CSV.parse(content, headers: true) rescue []

    @csv_import = CsvImport.create!(
      user: current_user,
      filename: uploaded.original_filename,
      csv_content: content,
      total_rows: rows.length
    )

    job = CsvImportJob.perform_later(csv_import_id: @csv_import.id, recipient: current_user)
    @csv_import.update!(job_id: job.job_id)

    redirect_to csv_import_path(@csv_import), notice: "Import started! Watch the progress below."
  end

  def show
    @csv_import = current_user.csv_imports.find(params[:id])
    @execution = ActiveJob::Notificare::Execution.find_by(job_id: @csv_import.job_id)
  end
end
