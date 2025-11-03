# frozen_string_literal: true

require_relative "lib/model_settings/version"

Gem::Specification.new do |spec|
  spec.name = "model_settings"
  spec.version = ModelSettings::VERSION
  spec.authors = ["Alexey Matskevich"]
  spec.email = ["github_job@mackevich.addymail.com"]

  spec.summary = "Declarative configuration management DSL for Rails models with multiple storage backends"
  spec.description = "ModelSettings provides a clean DSL for managing model configuration with support for column and JSON storage, validation framework, callback system, dirty tracking, query interface, deprecation tracking, I18n support, and extensible module architecture."
  spec.homepage = "https://github.com/AlexeyMatskevich/model_settings"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/AlexeyMatskevich/model_settings"
  spec.metadata["changelog_uri"] = "https://github.com/AlexeyMatskevich/model_settings/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activesupport", ">= 5.2"
  spec.add_dependency "activerecord", ">= 5.2"
  spec.add_dependency "railties", ">= 5.2" # For Rails generators

  # Development dependencies
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "standard", "~> 1.3"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "rubocop-factory_bot"
  spec.add_development_dependency "rubocop-rspec-guide", "~> 0.4.0"
  spec.add_development_dependency "store_model", "~> 2.0"
  spec.add_development_dependency "benchmark-ips", "~> 2.0"
  spec.add_development_dependency "simplecov", "~> 0.22"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
