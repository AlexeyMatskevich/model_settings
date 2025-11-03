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
    attr_reader :inheritable_options

    def initialize
      @default_modules = []
      @inherit_authorization = true # Security by default
      @inherit_settings = true # Inheritance enabled by default
      @module_callbacks = {}
      @inheritable_options = []
      @inheritable_options_explicitly_set = false
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

    # Set inheritable options explicitly
    #
    # When set explicitly by user, modules cannot auto-add their options.
    # This gives users full control over which options are inherited.
    #
    # @param options [Array<Symbol>] List of option names that should be inherited
    #
    # @example
    #   config.inheritable_options = [:viewable_by, :authorize_with]
    #
    def inheritable_options=(options)
      @inheritable_options = options
      @inheritable_options_explicitly_set = true
    end

    # Add an inheritable option (used by modules)
    #
    # Modules call this to automatically add their options to the inheritable list.
    # If user has explicitly set inheritable_options, this method does nothing
    # (user's explicit configuration takes precedence).
    #
    # @param option_name [Symbol] Name of the option to add
    #
    # @example In a module
    #   ModelSettings.configuration.add_inheritable_option(:authorize_with)
    #
    def add_inheritable_option(option_name)
      # If user explicitly set list - DON'T mutate
      return if @inheritable_options_explicitly_set

      # Add if not present
      @inheritable_options << option_name unless @inheritable_options.include?(option_name)
    end

    # Check if inheritable_options was explicitly set by user
    #
    # @return [Boolean] true if user explicitly set the list
    def inheritable_options_explicitly_set?
      @inheritable_options_explicitly_set
    end

    # Get effective inheritable options (user config + module registrations)
    #
    # Returns the final list of options that should be inherited by child settings.
    # If user explicitly set inheritable_options, only their list is used.
    # Otherwise, merges config.inheritable_options + ModuleRegistry.registered_inheritable_options
    #
    # @return [Array<Symbol>] List of options that should be inherited
    #
    # @example User explicitly set (user wins)
    #   config.inheritable_options = [:custom]
    #   ModuleRegistry.register_inheritable_option(:viewable_by)
    #   config.effective_inheritable_options
    #   # => [:custom]  (ignores module registration)
    #
    # @example User did not set (merge both)
    #   config.add_inheritable_option(:custom)
    #   ModuleRegistry.register_inheritable_option(:viewable_by)
    #   config.effective_inheritable_options
    #   # => [:custom, :viewable_by]  (merges both)
    #
    def effective_inheritable_options
      if @inheritable_options_explicitly_set
        # User explicitly set - only their list
        @inheritable_options
      else
        # Merge config + registered from modules (only those with auto_include: true)
        all_options = @inheritable_options.dup
        ModuleRegistry.registered_inheritable_options.each do |opt, config|
          if config[:auto_include] && !all_options.include?(opt)
            all_options << opt
          end
        end
        all_options
      end
    end

    # Reset configuration to defaults
    def reset!
      @default_modules = []
      @inherit_authorization = true
      @inherit_settings = true
      @module_callbacks = {}
      @inheritable_options = []
      @inheritable_options_explicitly_set = false
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
