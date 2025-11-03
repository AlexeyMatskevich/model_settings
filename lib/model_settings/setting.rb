# frozen_string_literal: true

module ModelSettings
  # Represents a single setting definition with its configuration and hierarchy
  #
  # Settings can be nested to create hierarchies, where child settings inherit
  # options from their parents unless explicitly overridden.
  #
  # @example Simple setting
  #   setting = Setting.new(:enabled, type: :column, default: false)
  #
  # @example Nested settings
  #   parent = Setting.new(:features, type: :json)
  #   child = Setting.new(:ai_enabled, {default: true}, parent: parent)
  #   parent.add_child(child)
  #
  class Setting
    # @return [Symbol] The name of the setting
    attr_reader :name

    # @return [Setting, nil] The parent setting (nil for root settings)
    attr_reader :parent

    # @return [Array<Setting>] Child settings
    attr_reader :children

    # @return [Hash] All options passed to the setting
    attr_reader :options

    # Initialize a new Setting
    #
    # @param name [Symbol] The name of the setting
    # @param options [Hash] Configuration options
    # @option options [Symbol] :type (:column) Storage type
    # @option options [Hash] :storage Storage configuration
    # @option options [Object] :default Default value
    # @option options [String] :description Human-readable description
    # @option options [Hash] :cascade Cascade configuration for enable/disable
    # @option options [Boolean, String] :deprecated Deprecation flag or message
    # @option options [Hash] :metadata Custom metadata
    # @option options [Symbol, Proc] :before_enable Callback before enabling
    # @option options [Symbol, Proc] :after_enable Callback after enabling
    # @option options [Symbol, Proc] :before_disable Callback before disabling
    # @option options [Symbol, Proc] :after_disable Callback after disabling
    # @param parent [Setting, nil] Optional parent setting for nested settings
    #
    def initialize(name, options = {}, parent: nil)
      @name = name.to_sym
      @options = options
      @parent = parent
      @children = []
    end

    # Add a child setting
    #
    # @param child [Setting] The child setting to add
    # @return [Setting] The added child setting
    # @raise [ArgumentError] if child is not a Setting
    def add_child(child)
      raise ArgumentError, "Child must be a Setting" unless child.is_a?(Setting)
      @children << child unless @children.include?(child)
      child
    end

    # Get the storage type for this setting
    #
    # Inherits parent's type if not explicitly specified, allowing nested settings
    # to naturally use the same storage as their parent.
    #
    # @return [Symbol] The storage type (:column, :json, :store_model)
    def type
      if @options.key?(:type)
        @options[:type]
      elsif parent
        parent.type
      else
        :column
      end
    end

    # Get the storage configuration
    #
    # @return [Hash] Storage configuration hash
    def storage
      @options.fetch(:storage, {})
    end

    # Get the default value
    #
    # @return [Object, nil] The default value
    def default
      @options[:default]
    end

    # Get the description
    #
    # @return [String, nil] The description
    def description
      @options[:description]
    end

    # Get the sync configuration
    #
    # @return [Hash, nil] Sync configuration with :mode and :target keys
    def sync
      @options[:sync]
    end

    # Check if setting is deprecated
    #
    # @return [Boolean] true if deprecated
    def deprecated?
      !!@options[:deprecated]
    end

    # Get deprecation reason
    #
    # @return [String, nil] The deprecation reason or nil if not deprecated
    def deprecation_reason
      return nil unless deprecated?

      case @options[:deprecated]
      when String
        @options[:deprecated]
      when true
        "Setting is deprecated"
      end
    end

    # Get custom metadata
    #
    # Includes inherited metadata from parent settings if inheritance is enabled.
    #
    # @return [Hash] Metadata hash
    def metadata
      all_inherited_options.fetch(:metadata, {})
    end

    # Check if setting has a metadata key
    #
    # Supports both symbol and string keys for flexibility.
    #
    # @param key [Symbol, String] Metadata key to check
    # @return [Boolean] true if metadata contains the key
    #
    # @example
    #   setting.has_metadata?(:tier) #=> true
    #   setting.has_metadata?("tier") #=> true
    #
    def has_metadata?(key)
      metadata.key?(key) || metadata.key?(key.to_s)
    end

    # Get metadata value for a key
    #
    # Supports both symbol and string keys, checking both variants.
    #
    # @param key [Symbol, String] Metadata key
    # @return [Object, nil] The metadata value or nil if not found
    #
    # @example
    #   setting.metadata_value(:tier) #=> :premium
    #   setting.metadata_value("tier") #=> :premium
    #
    def metadata_value(key)
      metadata[key] || metadata[key.to_s]
    end

    # Check if array metadata includes a value
    #
    # Returns false if the metadata key doesn't exist or isn't an array.
    #
    # @param key [Symbol, String] Metadata key
    # @param value [Object] Value to check for inclusion
    # @return [Boolean] true if the metadata value is an array containing the value
    #
    # @example
    #   setting.metadata_includes?(:plans, :enterprise) #=> true
    #   setting.metadata_includes?(:tier, :premium) #=> false (not an array)
    #
    def metadata_includes?(key, value)
      meta_value = metadata_value(key)
      meta_value.is_a?(Array) && meta_value.include?(value)
    end

    # Get cascade configuration
    #
    # Includes inherited cascade config from parent settings if inheritance is enabled.
    #
    # @return [Hash, nil] Cascade configuration hash or nil
    #
    # @example
    #   setting.cascade #=> {enable: true, disable: false}
    #
    def cascade
      all_inherited_options[:cascade]
    end

    # Get the path from root to this setting
    #
    # @return [Array<Symbol>] Array of setting names forming the path
    #
    # @example
    #   root.path #=> [:features]
    #   child.path #=> [:features, :ai_enabled]
    #
    def path
      if parent
        parent.path + [name]
      else
        [name]
      end
    end

    # Get the root setting (top-most parent)
    #
    # @return [Setting] The root setting (may be self if no parent)
    def root
      parent ? parent.root : self
    end

    # Check if this is a root setting
    #
    # @return [Boolean] true if setting has no parent
    def root?
      parent.nil?
    end

    # Check if this is a leaf setting
    #
    # @return [Boolean] true if setting has no children
    def leaf?
      children.empty?
    end

    # Find a child setting by name
    #
    # @param name [Symbol, String] The child setting name
    # @return [Setting, nil] The child setting or nil if not found
    def find_child(name)
      children.find { |child| child.name == name.to_sym }
    end

    # Get all descendants (children, grandchildren, etc.)
    #
    # @return [Array<Setting>] Array of all descendant settings
    def descendants
      children.flat_map { |child| [child] + child.descendants }
    end

    # Get an option value with inheritance from parent
    #
    # If the option is not set on this setting, looks up the parent chain.
    #
    # @param option_name [Symbol] The option name to look up
    # @return [Object, nil] The option value or nil if not found
    def inherited_option(option_name)
      if @options.key?(option_name)
        @options[option_name]
      elsif parent
        parent.inherited_option(option_name)
      end
    end

    # Get all callback options
    #
    # @return [Hash] Hash of callback names and their values
    def callbacks
      callback_keys = [
        :before_enable,
        :after_enable,
        :before_disable,
        :after_disable,
        :before_toggle,
        :after_toggle,
        :before_change,
        :after_change,
        :around_enable,
        :around_disable,
        :around_change,
        :after_enable_commit,
        :after_disable_commit,
        :after_change_commit
      ]

      @options.slice(*callback_keys)
    end

    # Check if setting has a specific option registered
    #
    # @param option_name [Symbol] The option name
    # @return [Boolean] true if option is present
    def has_option?(option_name)
      @options.key?(option_name)
    end

    # Get value for a registered option
    #
    # @param option_name [Symbol] The option name
    # @param default [Object] Default value if option not found
    # @return [Object] The option value or default
    def get_option(option_name, default = nil)
      @options.fetch(option_name, default)
    end

    # Get all registered custom options (excluding built-in options)
    #
    # @return [Hash] Hash of custom options
    def custom_options
      built_in_keys = [
        :type, :storage, :default, :description, :cascade, :deprecated,
        :metadata, :validate_with, :before_enable, :after_enable,
        :before_disable, :after_disable, :before_toggle, :after_toggle,
        :before_change, :after_change, :around_enable, :around_disable,
        :around_change, :after_enable_commit, :after_disable_commit,
        :after_change_commit, :sync, :requires
      ]

      @options.except(*built_in_keys)
    end

    # Deep merge options for inheritance
    #
    # Merges parent options with child options using configured merge strategies.
    # The merge strategy for each option is looked up from ModuleRegistry.
    #
    # @param parent_options [Hash] Parent setting options
    # @param child_options [Hash] Child setting options
    # @return [Hash] Merged options
    #
    # @see ModelSettings::ModuleRegistry.register_inheritable_option
    # @see ModelSettings::ModuleRegistry.merge_strategy_for
    def self.merge_inherited_options(parent_options, child_options)
      merged = parent_options.dup
      effective_list = ModelSettings.configuration.effective_inheritable_options

      child_options.each do |key, value|
        # Check if this option should be inherited
        if effective_list.include?(key)
          # Should inherit - apply merge strategy
          strategy = ModuleRegistry.merge_strategy_for(key) || :replace

          merged[key] = apply_merge_strategy(
            strategy: strategy,
            parent_value: merged[key],
            child_value: value,
            option_name: key
          )
        else
          # Should NOT inherit - child value only (replace)
          merged[key] = value
        end
      end

      merged
    end

    # Apply merge strategy to combine parent and child values
    #
    # @param strategy [Symbol] Merge strategy (:replace, :append, :merge)
    # @param parent_value [Object] Value from parent setting
    # @param child_value [Object] Value from child setting
    # @param option_name [Symbol] Option name (for error messages)
    # @return [Object] Merged value
    # @raise [ArgumentError] if type mismatch for :append or :merge
    #
    # @api private
    def self.apply_merge_strategy(strategy:, parent_value:, child_value:, option_name:)
      case strategy
      when :replace
        # Child value completely replaces parent value
        child_value

      when :append
        # Concatenate arrays (parent + child)
        # Both values must be Arrays (or nil)
        validate_array_merge!(parent_value, child_value, option_name)
        Array(parent_value) + Array(child_value)

      when :merge
        # Merge hashes (child keys override parent keys)
        # Both values must be Hashes (or nil)
        validate_hash_merge!(parent_value, child_value, option_name)
        (parent_value || {}).merge(child_value || {})

      else
        raise ArgumentError,
          "Unknown merge strategy: #{strategy.inspect} for option :#{option_name}"
      end
    end
    private_class_method :apply_merge_strategy

    # Validate that values can be merged as arrays
    #
    # @param parent_value [Object] Parent value
    # @param child_value [Object] Child value
    # @param option_name [Symbol] Option name for error message
    # @raise [ArgumentError] if values are not arrays (or nil)
    #
    # @api private
    def self.validate_array_merge!(parent_value, child_value, option_name)
      # Both values must be Arrays or nil
      parent_valid = parent_value.nil? || parent_value.is_a?(Array)
      child_valid = child_value.nil? || child_value.is_a?(Array)

      return if parent_valid && child_valid

      raise ArgumentError,
        "Cannot use :append merge strategy for :#{option_name} - " \
        "parent value is #{parent_value.class}, child value is #{child_value.class}. " \
        "Both must be Arrays (or nil)."
    end
    private_class_method :validate_array_merge!

    # Validate that values can be merged as hashes
    #
    # @param parent_value [Object] Parent value
    # @param child_value [Object] Child value
    # @param option_name [Symbol] Option name for error message
    # @raise [ArgumentError] if values are not hashes (or nil)
    #
    # @api private
    def self.validate_hash_merge!(parent_value, child_value, option_name)
      # Both values must be Hashes or nil
      parent_valid = parent_value.nil? || parent_value.is_a?(Hash)
      child_valid = child_value.nil? || child_value.is_a?(Hash)

      return if parent_valid && child_valid

      raise ArgumentError,
        "Cannot use :merge merge strategy for :#{option_name} - " \
        "parent value is #{parent_value.class}, child value is #{child_value.class}. " \
        "Both must be Hashes (or nil)."
    end
    private_class_method :validate_hash_merge!

    # Get all inheritable option values (including from parent chain)
    #
    # @return [Hash] Hash of all inherited options
    def all_inherited_options
      return @options.dup unless parent

      self.class.merge_inherited_options(parent.all_inherited_options, @options)
    end

    # Check if this setting needs its own storage adapter
    #
    # A setting needs its own adapter if:
    # - It's a root setting (no parent), OR
    # - It has explicit storage column configured, OR
    # - It's a column type (columns always use their own database column)
    #
    # Nested JSON/StoreModel settings without explicit storage use their parent's adapter.
    #
    # @return [Boolean] true if setting needs its own adapter
    def needs_own_adapter?
      # Root settings always need their own adapter
      return true if parent.nil?

      # Check for explicit storage configuration
      has_storage_column = storage[:column] || storage["column"]
      return true if has_storage_column

      # Column type always uses its own database column (named after the setting)
      # even when nested within a JSON parent
      return true if type == :column

      # Nested JSON/StoreModel settings without explicit storage use parent's adapter
      false
    end
  end
end
