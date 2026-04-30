require "test_helper"

class ActiveJob::Notificare::EngineTest < ActiveSupport::TestCase
  test "engine is loaded" do
    assert defined?(ActiveJob::Notificare::Engine)
  end

  test "engine is a Rails engine" do
    assert ActiveJob::Notificare::Engine < ::Rails::Engine
  end

  test "engine isolates namespace" do
    assert ActiveJob::Notificare::Engine.isolated?
  end

  test "engine is mountable in routes" do
    assert_respond_to ActiveJob::Notificare::Engine, :routes
  end
end
