# frozen_string_literal: true

module ModelSettings
  # Module registry for extending ModelSettings with custom modules
  #
  # Allows registration of exclusive module groups (like authorization)
  # and provides hooks for settings compilation and changes.
  #
  # Usage:
  #   ModelSettings::ModuleRegistry.register_module(:pundit, PunditModule)
  #   ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :pundit)
  #   ModelSettings::ModuleRegistry.on_settings_compiled { |settings| ... }
  #
  class ModuleRegistry
    # Error raised when trying to include conflicting modules from an exclusive group
    class ExclusiveGroupConflictError < StandardError; end
    class << self
      # Register a module
      #
      # @param name [Symbol] Module name
      # @param mod [Module] The module to register
      def register_module(name, mod)
        modules[name] = mod
      end

      # Register an exclusive group
      #
      # Exclusive groups ensure only one module from the group can be active
      # at a time (e.g., only Pundit OR ActionPolicy for authorization)
      #
      # @param group_name [Symbol] Group name (e.g., :authorization)
      # @param module_name [Symbol] Module name within the group
      def register_exclusive_group(group_name, module_name)
        exclusive_groups[group_name] ||= []
        exclusive_groups[group_name] << module_name unless exclusive_groups[group_name].include?(module_name)
      end

      # Register a custom option that can be used in setting definitions
      #
      # @param option_name [Symbol] Name of the option (e.g., :viewable_by, :ui_group)
      # @param validator [Proc, nil] Optional validator block that receives (setting, value)
      #
      # @example
      #   ModelSettings::ModuleRegistry.register_option(:viewable_by) do |setting, value|
      #     raise ArgumentError unless value.is_a?(Array)
      #   end
      #
      def register_option(option_name, validator = nil, &block)
        validator ||= block
        registered_options[option_name] = validator
      end

      # Extend Setting class with additional methods
      #
      # @param methods_module [Module] Module containing methods to add to Setting
      #
      # @example
      #   module SettingExtensions
      #     def custom_method
      #       # ...
      #     end
      #   end
      #   ModelSettings::ModuleRegistry.extend_setting(SettingExtensions)
      #
      def extend_setting(methods_module)
        ModelSettings::Setting.include(methods_module)
      end

      # Check if a module is included
      #
      # @param module_name [Symbol] Name of the module to check
      # @param model_class [Class] The model class to check
      # @return [Boolean] true if module is included
      def module_included?(module_name, model_class)
        return false unless modules.key?(module_name)

        mod = modules[module_name]
        model_class.included_modules.include?(mod)
      end

      # Register a hook to run when a setting is defined
      #
      # This hook runs immediately after a setting is created,
      # before any storage adapters are set up.
      #
      # @yield [setting, model_class] Block that receives the setting object and model class
      def on_setting_defined(&block)
        definition_hooks << block
      end

      # Register a hook to run when settings are compiled
      #
      # This hook runs after all settings are defined and adapters are set up,
      # typically when the class is fully loaded.
      #
      # @yield [settings, model_class] Block that receives the compiled settings array and model class
      def on_settings_compiled(&block)
        compilation_hooks << block
      end

      # Register a hook to run before a setting changes
      #
      # @yield [instance, setting, new_value] Block that receives the model instance, setting, and new value
      def before_setting_change(&block)
        before_change_hooks << block
      end

      # Register a hook to run after a setting changes
      #
      # @yield [instance, setting, old_value, new_value] Block that receives the model instance, setting, old and new values
      def after_setting_change(&block)
        after_change_hooks << block
      end

      # Get all registered modules
      #
      # @return [Hash] Hash of module name => module
      def modules
        @modules ||= {}
      end

      # Get all exclusive groups
      #
      # @return [Hash] Hash of group name => array of module names
      def exclusive_groups
        @exclusive_groups ||= {}
      end

      # Get all registered options
      #
      # @return [Hash] Hash of option name => validator proc
      def registered_options
        @registered_options ||= {}
      end

      # Get definition hooks
      #
      # @return [Array<Proc>] Array of definition hook blocks
      def definition_hooks
        @definition_hooks ||= []
      end

      # Get compilation hooks
      #
      # @return [Array<Proc>] Array of compilation hook blocks
      def compilation_hooks
        @compilation_hooks ||= []
      end

      # Get before_change hooks
      #
      # @return [Array<Proc>] Array of before_change hook blocks
      def before_change_hooks
        @before_change_hooks ||= []
      end

      # Get after_change hooks
      #
      # @return [Array<Proc>] Array of after_change hook blocks
      def after_change_hooks
        @after_change_hooks ||= []
      end

      # Check if a module is registered
      #
      # @param name [Symbol] Module name
      # @return [Boolean]
      def module_registered?(name)
        modules.key?(name)
      end

      # Get a registered module
      #
      # @param name [Symbol] Module name
      # @return [Module, nil]
      def get_module(name)
        modules[name]
      end

      # Check for conflicts when including a module
      #
      # This should be called in the `included` block of a module to prevent
      # conflicting modules from being included together.
      #
      # @param model_class [Class] The model class that's including the module
      # @param module_name [Symbol] Name of the module being included
      # @raise [ExclusiveGroupConflictError] if there's a conflict
      #
      # @example
      #   included do
      #     ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :roles)
      #   end
      #
      def check_exclusive_conflict!(model_class, module_name)
        exclusive_groups.each do |group_name, module_names|
          next unless module_names.include?(module_name)

          # Find other modules from the same group that are already included
          conflicting = module_names.find do |other_module|
            next if other_module == module_name
            module_included?(other_module, model_class)
          end

          if conflicting
            raise ExclusiveGroupConflictError,
              "Cannot include #{module_name.inspect} module: conflicts with #{conflicting.inspect} module " \
              "(both are in #{group_name.inspect} exclusive group). " \
              "Use only ONE authorization module at a time."
          end
        end
      end

      # Validate that exclusive groups don't have conflicts
      #
      # @param active_modules [Array<Symbol>] List of active module names
      # @return [Boolean] true if valid
      # @raise [ArgumentError] if there are conflicts
      def validate_exclusive_groups!(active_modules)
        exclusive_groups.each do |group_name, module_names|
          active_in_group = active_modules & module_names
          if active_in_group.size > 1
            raise ArgumentError, "Cannot use multiple modules from exclusive group '#{group_name}': #{active_in_group.join(", ")}"
          end
        end
        true
      end

      # Validate registered options for a setting
      #
      # @param setting [Setting] The setting to validate
      # @raise [ArgumentError] if validation fails
      def validate_setting_options!(setting)
        setting.options.each do |option_name, value|
          next unless registered_options.key?(option_name)

          validator = registered_options[option_name]
          next if validator.nil?

          validator.call(setting, value)
        end
      end

      # Execute definition hooks
      #
      # @param setting [Setting] The newly defined setting
      # @param model_class [Class] The model class
      def execute_definition_hooks(setting, model_class)
        definition_hooks.each do |hook|
          hook.call(setting, model_class)
        end
      end

      # Execute compilation hooks
      #
      # @param settings [Array<Setting>] The compiled settings
      # @param model_class [Class] The model class
      def execute_compilation_hooks(settings, model_class)
        compilation_hooks.each do |hook|
          hook.call(settings, model_class)
        end
      end

      # Execute before_change hooks
      #
      # @param instance [Object] The model instance
      # @param setting [Setting] The setting being changed
      # @param new_value [Object] The new value
      def execute_before_change_hooks(instance, setting, new_value)
        before_change_hooks.each do |hook|
          hook.call(instance, setting, new_value)
        end
      end

      # Execute after_change hooks
      #
      # @param instance [Object] The model instance
      # @param setting [Setting] The setting that changed
      # @param old_value [Object] The old value
      # @param new_value [Object] The new value
      def execute_after_change_hooks(instance, setting, old_value, new_value)
        after_change_hooks.each do |hook|
          hook.call(instance, setting, old_value, new_value)
        end
      end

      # Reset the registry (useful for testing)
      def reset!
        @modules = {}
        @exclusive_groups = {}
        @registered_options = {}
        @definition_hooks = []
        @compilation_hooks = []
        @before_change_hooks = []
        @after_change_hooks = []
      end
    end
  end
end
