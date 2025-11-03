# frozen_string_literal: true

# SimpleCov must be loaded before application code
require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter "/vendor/"

  add_group "Core", "lib/model_settings"
  add_group "Adapters", "lib/model_settings/adapters"
  add_group "Modules", "lib/model_settings/modules"
  add_group "Validators", "lib/model_settings/validators"
  add_group "Documentation", "lib/model_settings/documentation"

  enable_coverage :branch
  minimum_coverage line: 90, branch: 80
end

require "model_settings"

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
