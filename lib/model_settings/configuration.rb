# frozen_string_literal: true

module ModelSettings
  # Global configuration for ModelSettings
  #
  # Allows setting defaults for all models including default modules,
  # authorization inheritance, and other global settings.
  #
  # Example:
  #   ModelSettings.configure do |config|
  #     config.default_modules = [:pundit, :roles, :i18n]
  #     config.inherit_authorization = true
  #     config.inherit_settings = true
  #   end
  class Configuration
    attr_accessor :default_modules, :inherit_authorization, :inherit_settings

    def initialize
      @default_modules = []
      @inherit_authorization = true # Security by default
      @inherit_settings = true # Inheritance enabled by default
    end

    # Reset configuration to defaults
    def reset!
      @default_modules = []
      @inherit_authorization = true
      @inherit_settings = true
    end
  end

  class << self
    # Get the current configuration
    #
    # @return [Configuration] Current configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure ModelSettings globally
    #
    # @yield [Configuration] Yields configuration object for setup
    #
    # @example
    #   ModelSettings.configure do |config|
    #     config.default_modules = [:pundit, :ui, :i18n]
    #     config.inherit_authorization = true
    #   end
    def configure
      yield(configuration) if block_given?
    end

    # Reset configuration to defaults (useful for testing)
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
