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
      # This method solves the module reloading problem that occurs in RSpec and development mode.
      #
      # **Problem:** When using `included_modules.include?(ModuleConstant)`:
      # - In RSpec with eager loading, modules get reloaded between test runs
      # - Each reload creates a new Module object with different object identity
      # - Object identity comparison (`included_modules.include?(Module)`) fails because
      #   the Module constant now points to a different object than when it was included
      #
      # **Solution:** Symbol-based tracking instead of object identity:
      # - When a module is included, it registers itself in `_active_modules` array with a symbol
      # - `_active_modules` stores symbols like `:roles`, `:pundit`, `:action_policy`
      # - Symbols are stable across module reloads (they're always the same object)
      # - Symbol comparison (`_active_modules.include?(:pundit)`) works reliably
      #
      # **Example of the problem this solves:**
      # ```ruby
      # # Test 1: Include Pundit module
      # class User
      #   include ModelSettings::Modules::Pundit  # Module object: #<Module:0x1234>
      # end
      # User.included_modules.include?(ModelSettings::Modules::Pundit)  # true
      #
      # # Between tests, RSpec reloads ModelSettings::Modules::Pundit
      # # Now ModelSettings::Modules::Pundit is a NEW Module object: #<Module:0x5678>
      #
      # # Test 2: Check if Pundit is included
      # User.included_modules.include?(ModelSettings::Modules::Pundit)  # FALSE! (wrong object)
      # User._active_modules.include?(:pundit)  # TRUE! (symbol is stable)
      # ```
      #
      # @param module_name [Symbol] Name of the module to check
      # @param model_class [Class] The model class to check
      # @return [Boolean] true if module is included
      def module_included?(module_name, model_class)
        return false unless modules.key?(module_name)
        return false unless model_class.respond_to?(:_active_modules)

        # Use symbol-based tracking to avoid module reloading issues
        model_class._active_modules.include?(module_name)
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
            raise ArgumentError, ErrorMessages.module_conflict_error(group_name, active_in_group)
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

      # Register module callback configuration
      #
      # Allows modules to declare which Rails callback they use by default
      # and whether it can be configured globally.
      #
      # @param module_name [Symbol] Name of the module
      # @param default_callback [Symbol] Default Rails callback to use (e.g., :before_validation)
      # @param configurable [Boolean] Whether the callback can be changed via global configuration
      #
      # @example
      #   ModelSettings::ModuleRegistry.register_module_callback_config(
      #     :pundit,
      #     default_callback: :before_validation,
      #     configurable: true
      #   )
      #
      def register_module_callback_config(module_name, default_callback:, configurable: true)
        module_callback_configs[module_name] = {
          default_callback: default_callback,
          configurable: configurable
        }
      end

      # Get callback configuration for a module
      #
      # @param module_name [Symbol] Name of the module
      # @return [Hash, nil] Configuration hash or nil if not registered
      def get_module_callback_config(module_name)
        module_callback_configs[module_name]
      end

      # Get the active callback for a module
      #
      # Checks global configuration first, falls back to default if not configured.
      #
      # @param module_name [Symbol] Name of the module
      # @return [Symbol, nil] Callback name or nil if module not registered
      def get_module_callback(module_name)
        config = module_callback_configs[module_name]
        return nil unless config

        # Check if globally configured
        configured_callback = ModelSettings.configuration.get_module_callback(module_name)
        if configured_callback
          # Validate that module allows configuration
          unless config[:configurable]
            raise ArgumentError,
              "Module #{module_name.inspect} does not allow callback configuration " \
              "(configurable: false in registration)"
          end
          return configured_callback
        end

        # Fall back to default
        config[:default_callback]
      end

      # Get all registered module callback configurations
      #
      # @return [Hash] Hash of module name => config hash
      def module_callback_configs
        @module_callback_configs ||= {}
      end

      # Set module-specific metadata for a setting
      #
      # Stores metadata in the centralized _module_metadata storage.
      #
      # @param model_class [Class] The model class
      # @param module_name [Symbol] Name of the module
      # @param setting_name [Symbol] Name of the setting
      # @param metadata [Object] Metadata to store
      #
      # @example
      #   ModelSettings::ModuleRegistry.set_module_metadata(
      #     User, :roles, :billing, { viewable_by: [:admin], editable_by: [:admin] }
      #   )
      #
      def set_module_metadata(model_class, module_name, setting_name, metadata)
        # Ensure this class has its own isolated copy of _module_metadata hash
        # This prevents shared hash issues with class_attribute inheritance

        # Strategy: Before making the FIRST write for this module, check if we need isolation
        # We only need to check once per module per class
        current_meta = model_class._module_metadata

        # If this module doesn't exist in metadata yet, this is the first write
        # Check if we're sharing the hash object with parent or siblings
        unless current_meta.key?(module_name)
          # Check all ancestor classes (except Object/BasicObject)
          model_class.ancestors.each do |ancestor|
            next unless ancestor.is_a?(Class)
            next if [Object, BasicObject, ActiveRecord::Base].include?(ancestor)
            next unless ancestor.respond_to?(:_module_metadata)
            next if ancestor == model_class

            begin
              ancestor_meta = ancestor._module_metadata
              # If we share the same object with ANY ancestor, create our own copy
              if ancestor_meta && current_meta.equal?(ancestor_meta)
                model_class._module_metadata = current_meta.deep_dup
                current_meta = model_class._module_metadata
                break
              end
            rescue
              # Ancestor doesn't have _module_metadata, skip it
              next
            end
          end
        end

        # Initialize module hash if needed
        model_class._module_metadata[module_name] ||= {}
        # Set the metadata
        model_class._module_metadata[module_name][setting_name] = metadata
      end

      # Get module-specific metadata for a setting
      #
      # Retrieves metadata from the centralized _module_metadata storage.
      #
      # @param model_class [Class] The model class
      # @param module_name [Symbol] Name of the module
      # @param setting_name [Symbol, nil] Name of the setting (nil for all settings)
      # @return [Object, Hash, nil] Metadata value or hash of all settings
      #
      # @example Get specific setting metadata
      #   ModelSettings::ModuleRegistry.get_module_metadata(User, :roles, :billing)
      #   # => { viewable_by: [:admin], editable_by: [:admin] }
      #
      # @example Get all settings metadata for a module
      #   ModelSettings::ModuleRegistry.get_module_metadata(User, :roles)
      #   # => { billing: {...}, api_access: {...} }
      #
      def get_module_metadata(model_class, module_name, setting_name = nil)
        module_metadata = model_class._module_metadata[module_name] || {}
        setting_name ? module_metadata[setting_name] : module_metadata
      end

      # Check if module has metadata for a setting
      #
      # @param model_class [Class] The model class
      # @param module_name [Symbol] Name of the module
      # @param setting_name [Symbol] Name of the setting
      # @return [Boolean]
      #
      def module_metadata?(model_class, module_name, setting_name)
        model_class._module_metadata.dig(module_name, setting_name).present?
      end

      # Register a query method that a module provides
      #
      # This allows modules to declare which query methods they add to model classes,
      # enabling introspection similar to ActiveRecord's columns/associations API.
      #
      # @param module_name [Symbol] Module identifier
      # @param method_name [Symbol] Method name
      # @param scope [Symbol] Method scope (:class or :instance)
      # @param metadata [Hash] Optional metadata (description, parameters, return type)
      #
      # @example
      #   ModelSettings::ModuleRegistry.register_query_method(
      #     :roles,
      #     :settings_viewable_by,
      #     :class,
      #     description: "Get all settings viewable by a specific role",
      #     parameters: { role: :Symbol },
      #     returns: "Array<Symbol>"
      #   )
      #
      def register_query_method(module_name, method_name, scope, metadata = {})
        query_methods[module_name] ||= []
        query_methods[module_name] << {name: method_name, scope: scope, **metadata}
      end

      # Get all query methods for a module
      #
      # @param module_name [Symbol] Module identifier
      # @return [Array<Hash>] Array of method info hashes
      #
      # @example
      #   ModelSettings::ModuleRegistry.query_methods_for(:roles)
      #   # => [
      #   #   { name: :settings_viewable_by, scope: :class, description: "...", ... },
      #   #   { name: :can_view_setting?, scope: :instance, description: "...", ... }
      #   # ]
      #
      def query_methods_for(module_name)
        query_methods[module_name] || []
      end

      # Get all registered query methods
      #
      # @return [Hash] Hash of module_name => array of method info hashes
      #
      # @example
      #   ModelSettings::ModuleRegistry.query_methods
      #   # => { roles: [...], pundit: [...], ... }
      #
      def query_methods
        @query_methods ||= {}
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
        @module_callback_configs = {}
        @query_methods = {}
      end
    end
  end
end
