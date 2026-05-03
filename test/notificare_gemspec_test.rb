require "test_helper"
require "rubygems"

class NotificareGemspecTest < ActiveSupport::TestCase
  def spec
    @spec ||= Gem::Specification.load(File.expand_path("../notificare.gemspec", __dir__))
  end

  test "spec loads without error" do
    assert_instance_of Gem::Specification, spec
  end

  test "license is MIT" do
    assert_equal "MIT", spec.license
  end

  test "required_ruby_version covers >= 3.3" do
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.3.0")),
           "required_ruby_version should allow 3.3"
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.4.0")),
           "required_ruby_version should allow 3.4"
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.2.9")),
           "required_ruby_version should reject 3.2"
  end

  test "metadata contains required keys" do
    %w[source_code_uri changelog_uri bug_tracker_uri].each do |key|
      assert spec.metadata.key?(key), "metadata missing #{key}"
      assert_match %r{\Ahttps://}, spec.metadata[key], "#{key} should be an https URL"
    end
  end

  test "rubygems_mfa_required is true" do
    assert_equal "true", spec.metadata["rubygems_mfa_required"],
                 "rubygems_mfa_required must be \"true\""
  end

  test "spec.files excludes test/, coverage/, docs/, .github/" do
    forbidden_prefixes = %w[test/ coverage/ docs/ .github/]
    violations = spec.files.select do |f|
      forbidden_prefixes.any? { |prefix| f.start_with?(prefix) }
    end
    assert_empty violations, "spec.files must not include: #{violations.inspect}"
  end

  test "spec.files includes lib/, app/, config/, LICENSE, README.md" do
    assert spec.files.any? { |f| f.start_with?("lib/") }, "spec.files must include lib/"
    assert spec.files.any? { |f| f.start_with?("app/") }, "spec.files must include app/"
    assert spec.files.any? { |f| f.start_with?("config/") }, "spec.files must include config/"
    assert spec.files.include?("LICENSE"), "spec.files must include LICENSE"
    assert spec.files.include?("README.md"), "spec.files must include README.md"
  end
end
