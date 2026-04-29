require "rails/generators"
require "rails/generators/active_record"

module ActiveJob
  module Progress
    module Generators
      class InstallGenerator < Rails::Generators::Base
        include Rails::Generators::Migration

        source_root File.expand_path("templates", __dir__)

        def self.next_migration_number(dirname)
          ActiveRecord::Generators::Base.next_migration_number(dirname)
        end

        def create_migration_file
          migration_template(
            "create_active_job_progress_tables.rb.tt",
            "db/migrate/create_active_job_progress_tables.rb"
          )
        end

        def create_initializer
          template "initializer.rb.tt", "config/initializers/active_job_progress.rb"
        end

        def append_route_comment
          route "# mount ActiveJob::Progress::Engine => \"/job_progress\""
        end

        def create_view_partials
          create_file "app/views/active_job/progress/_progress.html.erb"
          create_file "app/views/active_job/progress/_notifications.html.erb"
        end

        private

        def json_column_type
          case ActiveRecord::Base.connection.adapter_name.downcase
          when /postgresql/, /postgis/
            "jsonb"
          when /mysql/
            "json"
          else
            "text"
          end
        end

        def migration_version
          "[#{ActiveRecord::Migration.current_version}]"
        end
      end
    end
  end
end
