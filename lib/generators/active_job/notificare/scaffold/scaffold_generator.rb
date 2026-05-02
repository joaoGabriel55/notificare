require "rails/generators"

module ActiveJob
  module Notificare
    module Generators
      class ScaffoldGenerator < Rails::Generators::NamedBase
        source_root File.expand_path("templates", __dir__)

        class_option :controller, type: :string,
          desc: "Override the controller class name (e.g. --controller=MyImportsController)"
        class_option :prefix, type: :string,
          desc: "Override the route and view directory prefix (e.g. --prefix=my_imports)"

        def validate_job_class
          klass = class_name.constantize
          unless klass.ancestors.include?(::ActiveJob::Notificare)
            say_status :error,
              "#{class_name} does not include ActiveJob::Notificare. " \
              "Add `include ActiveJob::Notificare` to the job class and re-run the generator.",
              :red
            @invalid = true
          end
        rescue NameError
          say_status :error,
            "#{class_name} could not be loaded. " \
            "Make sure the job class exists and includes `include ActiveJob::Notificare`.",
            :red
          @invalid = true
        end

        def create_controller
          return if @invalid
          template "controller.rb.tt", "app/controllers/#{prefix}_controller.rb"
        end

        def create_views
          return if @invalid
          template "index.html.erb.tt", "app/views/#{prefix}/index.html.erb"
          template "show.html.erb.tt", "app/views/#{prefix}/show.html.erb"
        end

        def create_locale
          return if @invalid
          template "locale.en.yml.tt", "config/locales/active_job_notificare_#{prefix}.en.yml"
        end

        def print_routes_snippet
          return if @invalid
          say "\nPaste into config/routes.rb:\n\n"
          say "  resources :#{prefix}, only: [:index, :show]", :green
          say ""
        end

        private

        def resource_name
          file_name.sub(/_job$/, "")
        end

        def plural_resource_name
          resource_name.pluralize
        end

        def prefix
          options[:prefix] || plural_resource_name
        end

        def scaffold_controller_class_name
          options[:controller] || "#{plural_resource_name.camelize}Controller"
        end
      end
    end
  end
end
