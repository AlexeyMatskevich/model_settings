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
      @module_callbacks = {}
    end

    # Configure callback for a specific module
    #
    # @param module_name [Symbol] Name of the module
    # @param callback_name [Symbol] Rails callback to use (e.g., :before_validation, :before_save)
    #
    # @example
    #   config.module_callback(:pundit, :before_save)
    #
    def module_callback(module_name, callback_name)
      @module_callbacks[module_name] = callback_name
    end

    # Get configured callback for a module
    #
    # @param module_name [Symbol] Name of the module
    # @return [Symbol, nil] Configured callback or nil if not set
    def get_module_callback(module_name)
      @module_callbacks[module_name]
    end

    # Get all configured module callbacks
    #
    # @return [Hash] Hash of module name => callback name
    attr_reader :module_callbacks

    # Reset configuration to defaults
    def reset!
      @default_modules = []
      @inherit_authorization = true
      @inherit_settings = true
      @module_callbacks = {}
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
