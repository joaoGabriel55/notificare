require "test_helper"

class ActiveJob::Notificare::VersionTest < ActiveSupport::TestCase
  test "VERSION is defined" do
    assert defined?(ActiveJob::Notificare::VERSION)
  end

  test "VERSION matches SemVer" do
    assert_match(/\A\d+\.\d+\.\d+/, ActiveJob::Notificare::VERSION)
  end

  test "VERSION matches rubygems prerelease shape" do
    assert_match(
      /\A\d+\.\d+\.\d+(\.[a-z]+(\.\d+)?)?\z/,
      ActiveJob::Notificare::VERSION,
      "VERSION must be a valid RubyGems version string (e.g. 0.1.0 or 0.1.0.alpha.1), " \
      "not Cargo-style (e.g. 0.1.0-alpha)"
    )
  end

  test "CHANGELOG.md top released heading matches VERSION" do
    changelog = File.read(File.expand_path("../../../CHANGELOG.md", __dir__))
    version = ActiveJob::Notificare::VERSION
    assert_match(
      /^## \[#{Regexp.escape(version)}\]/,
      changelog,
      "CHANGELOG.md must have a released section for #{version}. " \
      "Add '## [#{version}] - YYYY-MM-DD' before tagging."
    )
  end
end
