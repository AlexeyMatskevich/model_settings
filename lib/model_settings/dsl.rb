# frozen_string_literal: true

require "active_support/concern"

module ModelSettings
  # Core DSL module that provides the `setting` macro for ActiveRecord models
  #
  # Usage:
  #   class User < ApplicationRecord
  #     include ModelSettings::DSL
  #
  #     setting :notifications_enabled, type: :column, default: true
  #     setting :preferences, type: :json, storage: {column: :settings_data}
  #   end
  module DSL
    extend ActiveSupport::Concern

    included do
      # Ensure ModelSettings is only used with ActiveRecord models
      unless ancestors.include?(ActiveRecord::Base)
        raise ModelSettings::Error,
          "ModelSettings can only be included in ActiveRecord models. " \
          "#{name || "Anonymous class"} does not inherit from ActiveRecord::Base."
      end

      # Include core modules
      include ModelSettings::Callbacks
      include ModelSettings::Validation
      include ModelSettings::Deprecation
      include ModelSettings::Query

      # Store all settings defined on this model
      class_attribute :_settings, default: []

      # Store settings by name for quick lookup
      class_attribute :_settings_by_name, default: {}

      # Track if settings have been compiled
      class_attribute :_settings_compiled, default: false

      # Track active modules for this model
      class_attribute :_active_modules, default: []

      # Auto-include I18n module if available (for backward compatibility)
      if defined?(ModelSettings::Modules::I18n)
        include ModelSettings::Modules::I18n

        _active_modules << :i18n unless _active_modules.include?(:i18n)
      end

      # Auto-include default modules from configuration
      ModelSettings::DSL.auto_include_default_modules(self)

      # Dependency engine for cascades and syncs
      class_attribute :_dependency_engine

      # Hook into ActiveRecord lifecycle for cascades and syncs
      before_save :apply_setting_cascades_and_syncs if respond_to?(:before_save)
    end

    # Override initialize to compile settings before Rails assigns attributes
    #
    # This is critical because ActiveRecord's initialize assigns attributes
    # before after_initialize callbacks run, so we need adapters set up earlier.
    #
    # @param args [Array] Arguments passed to ActiveRecord initialize
    # @param block [Proc] Optional block passed to initialize
    def initialize(*args, &block)
      # Compile settings BEFORE calling super to ensure adapter methods exist
      # when ActiveRecord tries to assign attributes in the constructor
      self.class.compile_settings!
      super
    end

    # Auto-include default modules from configuration
    #
    # This method is called during DSL inclusion to automatically include
    # modules specified in ModelSettings.configuration.default_modules
    #
    # @param base [Class] The class that included ModelSettings::DSL
    # @return [void]
    def self.auto_include_default_modules(base)
      default_modules = ModelSettings.configuration.default_modules
      return if default_modules.nil? || default_modules.empty?

      default_modules.each do |module_name|
        module_class = resolve_module(module_name)
        next unless module_class

        # Include module if not already included
        unless base.included_modules.include?(module_class)
          base.include module_class
          base._active_modules << module_name
        end
      end
    end

    # Resolve module name (symbol) to module class
    #
    # Supports both built-in modules and external modules via constantize.
    #
    # @param module_name [Symbol] Module name (:roles, :pundit, :action_policy, :i18n, etc.)
    # @return [Module, nil] Module class or nil if not found
    #
    # @example
    #   resolve_module(:roles)        # => ModelSettings::Modules::Roles
    #   resolve_module(:custom_module) # => ModelSettings::Modules::CustomModule (if exists)
    def self.resolve_module(module_name)
      case module_name
      when :roles
        ModelSettings::Modules::Roles
      when :pundit
        ModelSettings::Modules::Pundit
      when :action_policy
        ModelSettings::Modules::ActionPolicy
      when :i18n
        ModelSettings::Modules::I18n
      else
        # Try to constantize for external modules
        "ModelSettings::Modules::#{module_name.to_s.camelize}".safe_constantize
      end
    rescue NameError
      nil
    end

    class_methods do
      # Hook called when class is inherited
      #
      # This is where we inherit settings from parent class.
      #
      # @param subclass [Class] The subclass being created
      # @return [void]
      def inherited(subclass)
        super

        if ModelSettings.configuration.inherit_settings && _settings.any?
          # Copy parent settings and create adapters for subclass
          inherited_settings = _settings.map do |parent_setting|
            # Create a new Setting object with same configuration
            setting_obj = Setting.new(
              parent_setting.name,
              parent_setting.options.dup,
              parent: parent_setting.parent
            )

            # Recursively copy children
            parent_setting.children.each do |child|
              child_copy = copy_setting_recursively(child, setting_obj)
              setting_obj.add_child(child_copy)
            end

            # Setup adapter for settings that need their own storage
            if setting_obj.needs_own_adapter?
              adapter = subclass.create_adapter_for(setting_obj)
              adapter.setup!
            end

            setting_obj
          end

          # Set inherited settings on subclass
          subclass._settings = inherited_settings
          subclass._settings_by_name = inherited_settings.index_by(&:name)
        else
          # When inheritance is disabled, reset settings to empty
          subclass._settings = []
          subclass._settings_by_name = {}
        end
      end

      # Define a setting on the model
      #
      # @param name [Symbol] The name of the setting
      # @param options [Hash] Configuration options for the setting
      # @option options [Symbol] :type (:column) Storage type - :column, :json, or :store_model
      # @option options [Hash] :storage Storage configuration (depends on type)
      # @option options [Object] :default Default value for the setting
      # @option options [String] :description Human-readable description
      # @option options [Symbol, Proc] :validate_with Validation callback
      # @option options [Hash] :cascade Cascade configuration {enable: true/false, disable: true/false}
      # @option options [Hash] :sync Sync configuration
      # @option options [Boolean, String] :deprecated Deprecation flag or message
      # @option options [Hash] :metadata Custom metadata hash
      # @yield Optional block for nested settings
      #
      # @example Simple column setting
      #   setting :enabled, type: :column, default: false
      #
      # @example JSON storage with nested settings
      #   setting :features, type: :json, storage: {column: :feature_flags} do
      #     setting :ai_enabled, default: false
      #     setting :analytics_enabled, default: true
      #   end
      #
      # @example With validation and callbacks
      #   setting :premium_mode,
      #           validate_with: :check_subscription,
      #           before_enable: :prepare_premium_features,
      #           after_enable: :notify_activation
      #
      def setting(name, options = {}, &block)
        parent_setting = @_current_setting_context

        # Check if we're overriding an inherited setting
        existing_setting = _settings_by_name[name] if !parent_setting

        if existing_setting && !parent_setting
          # Override inherited setting: merge options
          merged_options = Setting.merge_inherited_options(existing_setting.options, options)
          setting_obj = Setting.new(name, merged_options, parent: existing_setting.parent)

          # Replace in collections
          index = _settings.index(existing_setting)
          new_settings = _settings.dup
          new_settings[index] = setting_obj
          self._settings = new_settings
          self._settings_by_name = _settings_by_name.merge(name => setting_obj)
        else
          # Create new Setting object
          setting_obj = Setting.new(name, options, parent: parent_setting)

          # Add to parent or root collection
          if parent_setting
            parent_setting.add_child(setting_obj)
          else
            self._settings = _settings + [setting_obj]
            self._settings_by_name = _settings_by_name.merge(name => setting_obj)
          end
        end

        # Validate registered options
        ModelSettings::ModuleRegistry.validate_setting_options!(setting_obj)

        # Execute definition hooks
        ModelSettings::ModuleRegistry.execute_definition_hooks(setting_obj, self)

        # Validate storage configuration early (before deferred adapter setup)
        # This ensures configuration errors are caught during class definition
        if setting_obj.needs_own_adapter?
          validate_storage_configuration(setting_obj)
        end

        # Process nested settings if block given
        if block_given?
          previous_context = @_current_setting_context
          @_current_setting_context = setting_obj
          instance_eval(&block)
          @_current_setting_context = previous_context
        end

        # Note: Adapter setup is deferred to compile_settings! for wave-based compilation
        # This allows child settings to access parent settings during validation

        setting_obj
      end

      # Create the appropriate adapter for a setting
      #
      # @param setting [Setting] The setting object
      # @return [Adapters::Base] The adapter instance
      def create_adapter_for(setting)
        adapter_class = case setting.type
        when :column
          Adapters::Column
        when :json
          Adapters::Json
        when :store_model
          Adapters::StoreModel
        else
          raise ArgumentError, ErrorMessages.unknown_storage_type_error(
            setting.type,
            setting,
            self
          )
        end

        adapter_class.new(self, setting)
      end

      # Get all settings defined on this model
      #
      # @return [Array<Setting>] Array of Setting objects
      def settings
        compile_settings! # Ensure settings are compiled before access
        _settings
      end

      # Find a setting by name or path
      #
      # @param name_or_path [Symbol, Array<Symbol>] Setting name or path for nested settings
      # @return [Setting, nil] The setting object or nil if not found
      #
      # @example Find root setting
      #   User.find_setting(:notifications_enabled)
      #
      # @example Find nested setting
      #   User.find_setting([:features, :ai_enabled])
      #
      def find_setting(name_or_path)
        compile_settings! # Ensure settings are compiled before access

        if name_or_path.is_a?(Array)
          # Path to nested setting
          path = name_or_path
          current = _settings_by_name[path.first]
          return nil unless current

          path[1..].each do |name|
            current = current.find_child(name)
            return nil unless current
          end

          current
        else
          # Direct name lookup
          _settings_by_name[name_or_path.to_sym]
        end
      end

      # Get all root settings (settings without parents)
      #
      # @return [Array<Setting>] Array of root Setting objects
      def root_settings
        _settings.select(&:root?)
      end

      # Get all leaf settings (settings without children)
      #
      # @return [Array<Setting>] Array of leaf Setting objects
      def leaf_settings
        all_settings_recursive.select(&:leaf?)
      end

      # Get all settings including nested ones
      #
      # @return [Array<Setting>] Flattened array of all settings
      def all_settings_recursive
        _settings.flat_map { |s| [s] + s.descendants }
      end

      # Compile settings and run compilation hooks
      #
      # This method should be called after all settings are defined
      # (typically happens automatically when the class is loaded).
      # It processes settings in waves by nesting level, runs compilation
      # hooks, and marks settings as compiled.
      #
      # Wave-based compilation ensures parent settings are fully set up
      # before their children are processed, enabling proper inheritance
      # and dependency resolution.
      #
      # @return [void]
      def compile_settings!
        return if _settings_compiled

        # Group settings by depth (nesting level)
        settings_by_level = group_settings_by_depth

        # Process settings in waves: Level 0 → Level 1 → Level 2 → ...
        max_level = settings_by_level.keys.max || 0

        (0..max_level).each do |level|
          settings_at_level = settings_by_level[level] || []

          # Process each setting in definition order within the level
          settings_at_level.each do |setting|
            # Setup adapter if this setting needs its own storage
            if setting.needs_own_adapter?
              adapter = create_adapter_for(setting)
              adapter.setup!
            end
          end
        end

        # Execute compilation hooks
        ModelSettings::ModuleRegistry.execute_compilation_hooks(all_settings_recursive, self)

        # Initialize and compile dependency engine
        self._dependency_engine = DependencyEngine.new(self)
        _dependency_engine.compile!

        # Mark as compiled
        self._settings_compiled = true
      end

      # Add a module to the model's active modules list
      #
      # @param module_name [Symbol] Name of the module to activate
      # @return [void]
      def settings_add_module(module_name)
        return if _active_modules.include?(module_name)

        self._active_modules = _active_modules + [module_name]

        # Validate exclusive groups
        ModelSettings::ModuleRegistry.validate_exclusive_groups!(_active_modules)
      end

      # Configure model-specific settings
      #
      # @param options [Hash] Configuration options
      # @option options [Boolean] :inherit_authorization Whether to inherit authorization settings
      # @option options [Array<Symbol>] :modules Additional modules to include
      # @return [void]
      def settings_config(**options)
        options.each do |key, value|
          case key
          when :modules
            Array(value).each { |mod| settings_add_module(mod) }
          when :inherit_authorization
            # Store for later use by authorization modules
            class_attribute :_settings_inherit_authorization, default: value
          end
        end
      end

      # Configure modules for this model
      #
      # @param module_names [Array<Symbol>] Names of modules to activate
      # @return [void]
      def settings_modules(*module_names)
        module_names.flatten.each { |mod| settings_add_module(mod) }
      end

      # Debug helper: Print comprehensive settings information
      #
      # @return [void]
      #
      # @example
      #   User.settings_debug
      #
      def settings_debug
        puts "=" * 80
        puts "Settings Debug: #{name}"
        puts "=" * 80
        puts

        # Basic info
        puts "Total Settings: #{_settings.count}"
        puts "Root Settings: #{root_settings.count}"
        puts "Leaf Settings: #{leaf_settings.count}"
        puts "All Settings (including nested): #{all_settings_recursive.count}"
        puts

        # Active modules
        puts "Active Modules:"
        if _active_modules.any?
          _active_modules.each { |mod| puts "  - #{mod}" }
        else
          puts "  (none)"
        end
        puts

        # Storage columns
        if defined?(self::SETTINGS_COLUMNS)
          puts "Storage Columns:"
          self::SETTINGS_COLUMNS.each { |col| puts "  - #{col}" }
          puts
        end

        # Settings breakdown by type
        puts "Settings by Type:"
        all_settings_recursive.group_by(&:type).each do |type, settings|
          puts "  - #{type}: #{settings.count}"
        end
        puts

        # Deprecated settings
        deprecated = all_settings_recursive.select(&:deprecated?)
        puts "Deprecated Settings: #{deprecated.count}"
        if deprecated.any?
          deprecated.each do |setting|
            puts "  - #{setting.name}"
            message = setting.options[:deprecated]
            puts "    Message: #{message}" if message.is_a?(String)
          end
        end
        puts

        # Cascades
        cascaded = all_settings_recursive.select { |s| s.options[:cascade] }
        puts "Settings with Cascades: #{cascaded.count}"
        if cascaded.any?
          cascaded.each do |setting|
            config = setting.options[:cascade]
            modes = []
            modes << "enable" if config[:enable]
            modes << "disable" if config[:disable]
            puts "  - #{setting.name}: #{modes.join(", ")}"
          end
        end
        puts

        # Syncs
        synced = all_settings_recursive.select { |s| s.options[:sync] }
        puts "Settings with Syncs: #{synced.count}"
        if synced.any?
          synced.each do |setting|
            config = setting.options[:sync]
            target = config[:target] || config["target"]
            mode = config[:mode] || config["mode"] || :forward
            puts "  - #{setting.name} → #{target} (#{mode})"
          end
        end
        puts

        # Dependency graph
        if _dependency_engine
          puts "Sync Execution Order:"
          if _dependency_engine.sync_execution_order.any?
            _dependency_engine.sync_execution_order.each_with_index do |setting, i|
              puts "  #{i + 1}. #{setting.name}"
            end
          else
            puts "  (none)"
          end
        end
        puts

        puts "=" * 80
        nil
      end

      # Generate documentation for this model's settings
      #
      # @param format [Symbol] Output format (:markdown, :json, :yaml)
      # @param filter [Symbol, Proc] Filter settings (:active, :deprecated, or custom proc)
      # @return [String] Generated documentation
      #
      # @example Generate markdown documentation
      #   docs = User.settings_documentation(format: :markdown)
      #   File.write('docs/user_settings.md', docs)
      #
      # @example Generate JSON documentation
      #   docs = User.settings_documentation(format: :json)
      #
      # @example Generate YAML documentation
      #   docs = User.settings_documentation(format: :yaml)
      #
      # @example Generate HTML documentation
      #   docs = User.settings_documentation(format: :html)
      #
      def settings_documentation(format: :markdown, filter: nil)
        require_relative "documentation/markdown_formatter"
        require_relative "documentation/json_formatter"
        require_relative "documentation/yaml_formatter"
        require_relative "documentation/html_formatter"

        # Get all root settings
        settings_to_document = _settings.dup

        # Apply filter if provided
        if filter
          settings_to_document = apply_documentation_filter(settings_to_document, filter)
        end

        # Select formatter
        formatter_class = case format
        when :markdown
          Documentation::MarkdownFormatter
        when :json
          Documentation::JsonFormatter
        when :yaml
          Documentation::YamlFormatter
        when :html
          Documentation::HtmlFormatter
        else
          raise ArgumentError, ErrorMessages.unsupported_format_error(
            format,
            [:markdown, :json, :yaml, :html]
          )
        end

        formatter = formatter_class.new(self, settings_to_document)
        formatter.generate
      end

      private

      # Recursively copy a setting and all its children
      #
      # @param setting [Setting] The setting to copy
      # @param new_parent [Setting, nil] The parent for the copied setting
      # @return [Setting] The copied setting
      def copy_setting_recursively(setting, new_parent = nil)
        # Create a copy of the setting
        setting_copy = Setting.new(
          setting.name,
          setting.options.dup,
          parent: new_parent
        )

        # Recursively copy children
        setting.children.each do |child|
          child_copy = copy_setting_recursively(child, setting_copy)
          setting_copy.add_child(child_copy)
        end

        setting_copy
      end

      # Apply filter to settings list
      def apply_documentation_filter(settings, filter)
        case filter
        when :active
          settings.reject(&:deprecated?)
        when :deprecated
          settings.select(&:deprecated?)
        when Proc
          settings.select(&filter)
        else
          settings
        end
      end

      # Group all settings by their nesting depth level
      #
      # Returns a hash where keys are depth levels (0, 1, 2, ...)
      # and values are arrays of settings at that level, in definition order.
      #
      # @return [Hash{Integer => Array<Setting>}] Settings grouped by depth
      #
      # @example
      #   # Given:
      #   setting :billing do              # Level 0
      #     setting :invoices do           # Level 1
      #       setting :tax_reports         # Level 2
      #     end
      #     setting :payments              # Level 1
      #   end
      #   setting :api_access              # Level 0
      #
      #   # Returns:
      #   {
      #     0 => [:billing, :api_access],
      #     1 => [:invoices, :payments],
      #     2 => [:tax_reports]
      #   }
      def group_settings_by_depth
        settings_by_level = Hash.new { |h, k| h[k] = [] }

        all_settings_recursive.each do |setting|
          level = calculate_depth(setting)
          settings_by_level[level] << setting
        end

        settings_by_level
      end

      # Calculate the nesting depth of a setting
      #
      # Depth is determined by counting ancestors:
      # - Root settings have depth 0
      # - Direct children have depth 1
      # - Grandchildren have depth 2, etc.
      #
      # @param setting [Setting] The setting to calculate depth for
      # @return [Integer] The nesting depth (0 for root settings)
      #
      # @example
      #   calculate_depth(root_setting)    # => 0
      #   calculate_depth(child_setting)   # => 1
      #   calculate_depth(grandchild)      # => 2
      def calculate_depth(setting)
        depth = 0
        current = setting.parent
        while current
          depth += 1
          current = current.parent
        end
        depth
      end

      # Validate storage configuration for JSON and StoreModel adapters
      #
      # This validates storage config and type early during class definition,
      # before adapter setup is deferred to compile_settings!
      #
      # @param setting [Setting] The setting to validate
      # @raise [ArgumentError] If storage configuration or type is invalid
      def validate_storage_configuration(setting)
        # Validate storage type is recognized
        unless [:column, :json, :store_model].include?(setting.type)
          raise ArgumentError, ErrorMessages.unknown_storage_type_error(
            setting.type,
            setting,
            self
          )
        end

        # Validate storage configuration for adapters that require it
        case setting.type
        when :json
          storage = setting.storage
          unless storage.is_a?(Hash) && storage[:column]
            raise ArgumentError, ErrorMessages.adapter_configuration_error(
              :json,
              setting,
              self
            )
          end
        when :store_model
          storage = setting.storage
          unless storage.is_a?(Hash) && storage[:column]
            raise ArgumentError, ErrorMessages.adapter_configuration_error(
              :store_model,
              setting,
              self
            )
          end
        end
      end

      # Track current setting context for nested definitions
      attr_accessor :_current_setting_context
    end

    # Instance methods
    private

    # Apply cascades and syncs before saving
    #
    # This method detects which settings have changed and applies
    # cascades and syncs according to the dependency graph.
    #
    # @return [void]
    def apply_setting_cascades_and_syncs
      return unless self.class._dependency_engine

      # Find all changed root settings (check each root setting once)
      changed_root_settings = self.class.root_settings.select do |root_setting|
        adapter = self.class.create_adapter_for(root_setting)
        adapter.changed?(self)
      end

      # Collect all changed settings (root + descendants)
      changed_settings = changed_root_settings.flat_map do |root|
        [root] + root.descendants
      end.select do |setting|
        # Check if this specific setting changed

        public_send("#{setting.name}_changed?")
      rescue NoMethodError
        # For nested settings in JSON/StoreModel, check parent
        false
      end

      # Apply cascades and syncs
      self.class._dependency_engine.execute_cascades_and_syncs(self, changed_settings)
    end
  end
end
