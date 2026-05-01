# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_01_024834) do
  create_table "active_job_executions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "current_step"
    t.text "error"
    t.string "job_class", null: false
    t.string "job_id", null: false
    t.integer "progress_current", default: 0, null: false
    t.integer "progress_total"
    t.datetime "started_at"
    t.string "status", default: "enqueued", null: false
    t.datetime "updated_at", null: false
    t.index ["job_class"], name: "index_active_job_executions_on_job_class"
    t.index ["job_id"], name: "index_active_job_executions_on_job_id", unique: true
  end

  create_table "active_job_notifications", force: :cascade do |t|
    t.text "actions"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "dismissed_at"
    t.string "event_type", null: false
    t.string "job_id"
    t.text "metadata"
    t.datetime "read_at"
    t.string "recipient_id", null: false
    t.string "recipient_type", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_active_job_notifications_on_job_id"
    t.index ["recipient_id"], name: "index_active_job_notifications_on_recipient_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end
end
