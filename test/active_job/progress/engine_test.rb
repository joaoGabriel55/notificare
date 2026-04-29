require "test_helper"

class ActiveJob::Progress::EngineTest < ActiveSupport::TestCase
  test "engine is loaded" do
    assert defined?(ActiveJob::Progress::Engine)
  end

  test "engine is a Rails engine" do
    assert ActiveJob::Progress::Engine < ::Rails::Engine
  end

  test "engine isolates namespace" do
    assert ActiveJob::Progress::Engine.isolated?
  end

  test "engine is mountable in routes" do
    assert_respond_to ActiveJob::Progress::Engine, :routes
  end
end
