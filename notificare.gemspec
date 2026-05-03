Gem::Specification.new do |spec|
  spec.name        = "notificare"
  spec.version     = File.read(File.join(__dir__, "lib/active_job/notificare/version.rb"))
                         .match(/VERSION\s*=\s*["']([^"']+)["']/)[1]
  spec.authors     = ["Gabriel Quaresma"]
  spec.email       = ["j.quaresmasantos_98@hotmail.com"]
  spec.summary     = "Progress tracking and notification inbox for ActiveJob::Continuation"
  spec.description = "Notificare (Romanian: 'to notify') is a Rails engine built on top of ActiveJob::Continuation. " \
                     "It adds a persisted projection of running-job progress, a durable user-facing notification inbox, " \
                     "and a Hotwire UI scaffold — turning Continuation's resumable steps into a state machine that " \
                     "drives notifications without manual broadcast plumbing."
  spec.homepage    = "https://github.com/joaoGabriel55/notificare"
  spec.license     = "MIT"

  spec.required_ruby_version    = ">= 3.3"
  spec.required_rubygems_version = ">= 3.5"

  spec.metadata = {
    "homepage_uri"        => "https://github.com/joaoGabriel55/notificare",
    "source_code_uri"     => "https://github.com/joaoGabriel55/notificare",
    "changelog_uri"       => "https://github.com/joaoGabriel55/notificare/blob/v0.1.0.alpha.1/CHANGELOG.md",
    "bug_tracker_uri"     => "https://github.com/joaoGabriel55/notificare/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "LICENSE",
    "README.md"
  ]
  spec.require_paths = ["lib"]

  # ActiveJob::Continuation ships with activejob >= 8.1 — that's the seam this gem projects from.
  spec.add_dependency "railties", ">= 8.1"
  spec.add_dependency "activejob", ">= 8.1"
end
