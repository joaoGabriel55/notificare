# Notificare Demo App

A real-world example Rails application that demonstrates the [`notificare`](https://github.com/joaoGabriel55/notificare) gem — live job progress tracking and a durable notification inbox, powered by Hotwire and ActiveJob.

## What this demo does

The app simulates a **CSV contact import** workflow:

1. User uploads a CSV file with `name`, `email`, and optional `phone` columns.
2. A background job (`CsvImportJob`) processes the file in three steps:
   - **validate_file** — checks that required columns are present.
   - **process_rows** — iterates every row, updating progress in real time.
   - **finalize** — marks the import as completed.
3. The import detail page shows a **live progress bar** that updates via Turbo Streams as rows are processed.
4. On completion (or failure), a **notification** appears in the inbox on the same page — no polling, no page refresh.

## Setup

This app is part of the `notificare` gem repository. It depends on the gem via a local `path:` reference.

```bash
# From this directory (test/dummy/)
bundle install

# Create the main tables (users, csv_imports, active_job_executions/notifications)
bin/rails db:migrate

# Create and load the Solid Queue tables into the queue database
bin/rails runner "
  ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: 'storage/development_queue.sqlite3')
  load Rails.root.join('db/queue_schema.rb')
"

# Seed the demo user
bin/rails db:seed
```

## Running the development server

Open two terminals from `test/dummy/`:

**Terminal 1 — web server:**
```bash
bin/rails server
```

**Terminal 2 — job worker:**
```bash
bin/rails solid_queue:start
```

Then open http://localhost:3000.

## Admin UI

The notificare engine admin UI is mounted at `/notificare`. It shows all execution records, live step progress, and filters by status or job class.

## CSV format

Upload a CSV with at minimum a `name` and `email` column:

```
name,email,phone
Alice Smith,alice@example.com,+1-555-0101
Bob Jones,bob@example.com,
```

## Key files

| File | Purpose |
|---|---|
| `app/jobs/csv_import_job.rb` | The demo job: 3 steps, progress tracking, step + lifecycle notifications |
| `app/controllers/csv_imports_controller.rb` | Upload form, enqueue job, show live progress |
| `app/views/csv_imports/` | Index list, upload form, show page with progress and inbox |
| `config/initializers/active_job_notificare.rb` | Notificare config: open auth, current_recipient_proc |
