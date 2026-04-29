Gem::Specification.new do |spec|
  spec.name        = "koraci"
  spec.version     = File.read(File.join(__dir__, "lib/active_job/progress/version.rb"))
                         .match(/VERSION\s*=\s*["']([^"']+)["']/)[1]
  spec.authors     = ["Gabriel Quaresma"]
  spec.email       = ["j.quaresmasantos_98@hotmail.com"]
  spec.summary     = "ActiveJob progress tracking as a Rails engine"
  spec.description = "Koraci adds first-class progress tracking to ActiveJob jobs."
  spec.homepage    = "https://github.com/joaoGabriel55/koraci"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.3"

  spec.files = Dir[
    "lib/**/*",
    "app/**/*",
    "config/**/*",
    "LICENSE",
    "README.md"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "activejob", ">= 8.0"
end
