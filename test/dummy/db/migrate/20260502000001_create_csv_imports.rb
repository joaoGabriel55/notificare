class CreateCsvImports < ActiveRecord::Migration[8.1]
  def change
    create_table :csv_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      t.text :csv_content, null: false
      t.string :status, null: false, default: "pending"
      t.integer :total_rows, null: false, default: 0
      t.integer :processed_rows, null: false, default: 0
      t.string :job_id
      t.datetime :completed_at
      t.timestamps
    end
  end
end
