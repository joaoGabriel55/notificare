require "test_helper"

class ActiveJob::Progress::VersionTest < ActiveSupport::TestCase
  test "VERSION is defined" do
    assert defined?(ActiveJob::Progress::VERSION)
  end

  test "VERSION matches SemVer" do
    assert_match(/\A\d+\.\d+\.\d+/, ActiveJob::Progress::VERSION)
  end
end
