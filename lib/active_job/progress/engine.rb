module ActiveJob
  module Progress
    class Engine < ::Rails::Engine
      isolate_namespace ActiveJob::Progress
    end
  end
end
