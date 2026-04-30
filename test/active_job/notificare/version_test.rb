require "test_helper"

class ActiveJob::Notificare::VersionTest < ActiveSupport::TestCase
  test "VERSION is defined" do
    assert defined?(ActiveJob::Notificare::VERSION)
  end

  test "VERSION matches SemVer" do
    assert_match(/\A\d+\.\d+\.\d+/, ActiveJob::Notificare::VERSION)
  end
end
