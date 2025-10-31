# frozen_string_literal: true

require "set"

module ModelSettings
  module Adapters
    # JSON adapter for storing multiple settings in a single JSON column
    #
    # Creates custom accessors for JSON keys with dirty tracking.
    # Supports both single values and arrays.
    #
    # Requirements:
    # - JSON column must exist in database (via migration)
    # - Column should be jsonb or json type
    #
    # Features:
    # - Multiple settings in one column
    # - Array support with `array: true`
    # - Dirty tracking via ActiveRecord::AttributeMethods::Dirty
    # - Helper methods (enable!, disable!, toggle!)
    #
    # Example migration:
    #   add_column :users, :settings, :jsonb, default: {}, null: false
    #
    # Example usage:
    #   class User < ApplicationRecord
    #     include ModelSettings::DSL
    #
    #     setting :features, type: :json, storage: {column: :settings} do
    #       setting :billing_enabled, default: false
    #       setting :speech_recognition, default: false
    #     end
    #   end
    #
    #   user.billing_enabled = true
    #   user.billing_enabled_changed? # => true
    class Json < Base
      def setup!
        setting_name = setting.name
        column_name = storage_column
        setting_obj = setting

        # Setup JSON serialization for the storage column if this is a root JSON setting
        # This ensures t.text columns properly serialize/deserialize JSON data
        if setting.needs_own_adapter?
          setup_column_serialization(column_name)
        end

        # Check if this is array membership pattern
        if array_membership?
          # Setup array membership accessors (different behavior)
          setup_array_membership!(column_name, setting_name)
        else
          # Setup regular JSON accessor methods
          setup_accessors(column_name, setting_name)
        end

        # Define enable! helper method with callbacks
        model_class.define_method("#{setting_name}_enable!") do
          # Execute before_enable callback
          execute_setting_callbacks(setting_obj, :enable, :before)

          # Execute around_enable callback (wraps the value assignment)
          execute_around_callback(setting_obj, :enable) do
            # Set the value
            public_send("#{setting_name}=", true)
          end

          # Execute after_enable callback
          execute_setting_callbacks(setting_obj, :enable, :after)

          # Track for after_commit if needed
          track_setting_change_for_commit(setting_obj) if setting_obj.options[:after_change_commit]
        end

        # Define disable! helper method with callbacks
        model_class.define_method("#{setting_name}_disable!") do
          # Execute before_disable callback
          execute_setting_callbacks(setting_obj, :disable, :before)

          # Execute around_disable callback (wraps the value assignment)
          execute_around_callback(setting_obj, :disable) do
            # Set the value
            public_send("#{setting_name}=", false)
          end

          # Execute after_disable callback
          execute_setting_callbacks(setting_obj, :disable, :after)

          # Track for after_commit if needed
          track_setting_change_for_commit(setting_obj) if setting_obj.options[:after_change_commit]
        end

        # Define toggle! helper method with callbacks
        model_class.define_method("#{setting_name}_toggle!") do
          # Execute before_toggle callback
          execute_setting_callbacks(setting_obj, :toggle, :before)

          # Toggle the value
          current = public_send(setting_name)
          public_send("#{setting_name}=", !current)

          # Execute after_toggle callback
          execute_setting_callbacks(setting_obj, :toggle, :after)

          # Track for after_commit if needed
          track_setting_change_for_commit(setting_obj) if setting_obj.options[:after_change_commit]
        end

        # Define enabled? helper
        model_class.define_method("#{setting_name}_enabled?") do
          !!public_send(setting_name)
        end

        # Define disabled? helper
        model_class.define_method("#{setting_name}_disabled?") do
          !public_send(setting_name)
        end

        # Add Rails validation to ensure only boolean values (only for boolean settings)
        # Skip validation for:
        # - Settings with nested children (parent containers)
        # - Array-type settings (array: true option)
        is_array_setting = setting.options[:array] == true

        # Add validation unless validate: false, has children, or is array setting
        should_validate = setting.options[:validate] != false && !setting.children.any? && !is_array_setting
        model_class.validates setting_name, boolean_value: true if should_validate

        # Setup nested settings if any
        setup_nested_settings(column_name) if setting.children.any?
      end

      def read(instance)
        instance.public_send(setting.name)
      end

      def write(instance, value)
        instance.public_send("#{setting.name}=", value)
      end

      def changed?(instance)
        instance.public_send("#{setting.name}_changed?")
      end

      def was(instance)
        instance.public_send("#{setting.name}_was")
      end

      def change(instance)
        instance.public_send("#{setting.name}_change")
      end

      private

      # Get the column name from storage configuration
      def storage_column
        storage = setting.storage
        return storage[:column] if storage.is_a?(Hash) && storage[:column]
        raise ArgumentError, "JSON adapter requires storage: {column: :column_name}"
      end

      # Check if this setting uses array membership pattern
      #
      # @return [Boolean] true if storage has array: true option
      def array_membership?
        storage = setting.storage
        storage.is_a?(Hash) && storage[:array] == true
      end

      # Get the value to use in the array
      #
      # Defaults to setting name if array_value not specified.
      # This allows custom values for legacy compatibility or renaming.
      #
      # @return [String] the value to store/check in the array
      def array_value
        storage = setting.storage
        return storage[:array_value].to_s if storage.is_a?(Hash) && storage[:array_value]
        setting.name.to_s
      end

      # Setup JSON serialization for a column
      #
      # This ensures that text columns properly serialize/deserialize JSON data.
      # For databases with native JSON support (PostgreSQL jsonb), this is automatic.
      # For text columns, we need to explicitly configure serialization.
      #
      # @param column_name [Symbol] The column to configure
      # @return [void]
      def setup_column_serialization(column_name)
        # Track which columns we've already configured to avoid duplicate setup
        # Use class-level tracking since multiple adapter instances may exist
        ivar_name = :@_json_serialized_columns
        configured_columns = model_class.instance_variable_get(ivar_name) || []
        return if configured_columns.include?(column_name)

        # Check column type - native JSON columns don't need serialization
        # Rescue ArgumentError for anonymous classes used in tests
        if model_class.respond_to?(:columns_hash)
          begin
            column = model_class.columns_hash[column_name.to_s]
            if column
              # PostgreSQL jsonb/json types handle serialization automatically
              if [:jsonb, :json].include?(column.type)
                model_class.instance_variable_set(ivar_name, configured_columns + [column_name])
                return
              end
            end
          rescue ArgumentError
            # Anonymous classes don't have table names, just proceed with serialization
          end
        end

        # Setup ActiveRecord serialization for text columns
        # This converts Hash <-> String automatically on read/write
        # In ActiveRecord 8+, use coder: JSON
        model_class.serialize(column_name, coder: JSON)
        model_class.instance_variable_set(ivar_name, configured_columns + [column_name])
      end

      # Setup accessor methods for a setting within a JSON column
      def setup_accessors(column_name, setting_name)
        column_sym = column_name.to_sym
        setting_sym = setting_name.to_sym
        setting_str = setting_name.to_s
        default_value = setting.options[:default]
        # If this setting has its own storage column, it's a root JSON setting
        # Otherwise, find the root JSON storage setting by walking up the parent chain
        if setting.storage[:column] || setting.storage["column"]
          # This setting has explicit storage - it's root for itself
          root_json_setting = setting
        else
          # Find parent JSON setting with storage
          root_json_setting = nil
          current = setting.parent
          while current
            if current.options[:type] == :json && current.storage[:column]
              root_json_setting = current
              break
            end
            current = current.parent
          end
        end

        # Calculate path relative to root JSON setting
        if setting.options[:nested_key]
          nested_key_path = setting.options[:nested_key]
        elsif root_json_setting.nil? || root_json_setting == setting
          # This is the root JSON setting itself or no JSON storage found
          nested_key_path = [setting.name]
        else
          # Get full path from root JSON setting to current setting
          path_from_root = []
          current = setting
          while current && current != root_json_setting
            path_from_root.unshift(current.name)
            current = current.parent
          end
          # Add root setting name at the beginning
          path_from_root.unshift(root_json_setting.name)
          nested_key_path = path_from_root
        end

        # Track that we're managing this setting
        add_managed_setting(column_sym, setting_sym)

        # Define getter method
        model_class.define_method(setting_sym) do
          raw_data = public_send(column_sym)
          # Ensure data is Hash, initialize if nil or non-Hash
          data = raw_data.is_a?(Hash) ? raw_data : {}

          # Navigate through nested keys if needed
          if nested_key_path && nested_key_path.size > 1
            # Check if nested path exists
            current = data
            path_exists = nested_key_path[0..-2].all? do |key|
              current = current[key.to_s] if current.is_a?(Hash)
              current.is_a?(Hash)
            end

            if path_exists && current.is_a?(Hash) && current.key?(nested_key_path.last.to_s)
              current[nested_key_path.last.to_s]
            else
              default_value
            end
          else
            # Simple key lookup
            data.key?(setting_str) ? data[setting_str] : default_value
          end
        end

        # Define setter method with dirty tracking
        model_class.define_method("#{setting_sym}=") do |value|
          data = public_send(column_sym) || {}

          # Handle nested keys
          if nested_key_path && nested_key_path.size > 1
            # Build nested structure
            current = data
            nested_key_path[0..-2].each do |key|
              key_str = key.to_s
              current[key_str] ||= {}
              current = current[key_str]
            end
            current[nested_key_path.last.to_s] = value
          else
            data[setting_str] = value
          end

          public_send("#{column_sym}=", data)
        end

        # Define changed? method
        model_class.define_method("#{setting_sym}_changed?") do
          return false unless public_send("#{column_sym}_changed?")

          old_data = public_send("#{column_sym}_was") || {}
          new_data = public_send(column_sym) || {}

          # Extract old and new values considering nested keys
          old_value = if nested_key_path && nested_key_path.size > 1
            nested_key_path.reduce(old_data) do |hash, key|
              hash.is_a?(Hash) ? hash[key.to_s] : nil
            end
          else
            old_data[setting_str]
          end

          new_value = if nested_key_path && nested_key_path.size > 1
            nested_key_path.reduce(new_data) do |hash, key|
              hash.is_a?(Hash) ? hash[key.to_s] : nil
            end
          else
            new_data[setting_str]
          end

          # Compare values (arrays use deep comparison automatically)
          old_value != new_value
        end

        # Define _was method
        model_class.define_method("#{setting_sym}_was") do
          old_data = public_send("#{column_sym}_was") || {}

          if nested_key_path && nested_key_path.size > 1
            # Check if nested path exists
            current = old_data
            path_exists = nested_key_path[0..-2].all? do |key|
              current = current[key.to_s] if current.is_a?(Hash)
              current.is_a?(Hash)
            end

            if path_exists && current.is_a?(Hash) && current.key?(nested_key_path.last.to_s)
              current[nested_key_path.last.to_s]
            else
              default_value
            end
          else
            old_data.key?(setting_str) ? old_data[setting_str] : default_value
          end
        end

        # Define _change method
        model_class.define_method("#{setting_sym}_change") do
          return nil unless public_send("#{setting_sym}_changed?")

          [public_send("#{setting_sym}_was"), public_send(setting_sym)]
        end
      end

      # Track managed settings for a column
      def add_managed_setting(column_name, setting_name)
        ivar_name = :"@_json_settings_#{column_name}"
        settings = model_class.instance_variable_get(ivar_name) || []
        settings << setting_name unless settings.include?(setting_name)
        model_class.instance_variable_set(ivar_name, settings)
      end

      # Setup nested settings within the same JSON column
      def setup_nested_settings(column_name)
        setting.children.each do |child_setting|
          # Skip children that need their own adapter (explicit storage column)
          # Those are handled by the DSL directly
          next if child_setting.needs_own_adapter?

          child_name = child_setting.name

          # Create adapter for child setting and setup accessors
          # Validation is already included in setup_accessors setter
          child_adapter = self.class.new(model_class, child_setting)
          child_adapter.send(:setup_accessors, column_name, child_name)

          # Define helper methods for nested settings with callbacks
          model_class.define_method("#{child_name}_enable!") do
            # Execute before_enable callback
            execute_setting_callbacks(child_setting, :enable, :before)

            # Execute around_enable callback (wraps the value assignment)
            execute_around_callback(child_setting, :enable) do
              # Set the value
              public_send("#{child_name}=", true)
            end

            # Execute after_enable callback
            execute_setting_callbacks(child_setting, :enable, :after)

            # Track for after_commit if needed
            track_setting_change_for_commit(child_setting) if child_setting.options[:after_change_commit]
          end

          model_class.define_method("#{child_name}_disable!") do
            # Execute before_disable callback
            execute_setting_callbacks(child_setting, :disable, :before)

            # Execute around_disable callback (wraps the value assignment)
            execute_around_callback(child_setting, :disable) do
              # Set the value
              public_send("#{child_name}=", false)
            end

            # Execute after_disable callback
            execute_setting_callbacks(child_setting, :disable, :after)

            # Track for after_commit if needed
            track_setting_change_for_commit(child_setting) if child_setting.options[:after_change_commit]
          end

          model_class.define_method("#{child_name}_toggle!") do
            # Execute before_toggle callback
            execute_setting_callbacks(child_setting, :toggle, :before)

            # Toggle the value
            current = public_send(child_name)
            public_send("#{child_name}=", !current)

            # Execute after_toggle callback
            execute_setting_callbacks(child_setting, :toggle, :after)

            # Track for after_commit if needed
            track_setting_change_for_commit(child_setting) if child_setting.options[:after_change_commit]
          end

          model_class.define_method("#{child_name}_enabled?") do
            !!public_send(child_name)
          end

          model_class.define_method("#{child_name}_disabled?") do
            !public_send(child_name)
          end

          # Add Rails validation for nested setting (only for boolean settings)
          # Skip validation for:
          # - Settings with nested children (parent containers)
          # - Array-type settings (array: true option)
          # - Settings with validate: false option
          is_array_setting = child_setting.options[:array] == true

          should_validate = child_setting.options[:validate] != false && !child_setting.children.any? && !is_array_setting
          model_class.validates child_name, boolean_value: true if should_validate

          # Recursively setup nested settings for grandchildren
          if child_setting.children.any?
            child_adapter.send(:setup_nested_settings, column_name)
          end
        end
      end

      # Setup array membership accessors and dirty tracking
      #
      # Array membership pattern stores settings as string values in a JSON array.
      # The getter returns true if value is in array, false otherwise.
      # The setter adds/removes the value from the array.
      #
      # @param column_name [Symbol] The JSON column name
      # @param setting_name [Symbol] The setting name
      # @return [void]
      def setup_array_membership!(column_name, setting_name)
        setting_sym = setting_name.to_sym
        column_sym = column_name.to_sym
        setting_name.to_s
        value_to_store = array_value

        # Track that we're managing this setting
        add_managed_setting(column_sym, setting_sym)

        # Getter: returns true if value is in array, false otherwise
        model_class.define_method(setting_sym) do
          array = public_send(column_sym)
          # Handle nil or non-array (validation will catch non-array)
          return false unless array.is_a?(Array)
          array.include?(value_to_store)
        end

        # Setter: adds to array when true, removes when false
        model_class.define_method("#{setting_sym}=") do |enabled|
          array = public_send(column_sym)
          # Initialize as empty array if nil or non-array
          array = [] unless array.is_a?(Array)
          # Duplicate array to trigger dirty tracking
          array = array.dup

          if enabled
            # Add value if not already present (avoid duplicates)
            array << value_to_store unless array.include?(value_to_store)
          else
            # Remove all occurrences of the value
            array.delete(value_to_store)
          end

          public_send("#{column_sym}=", array)
        end

        # Dirty tracking: _changed?
        model_class.define_method("#{setting_sym}_changed?") do
          return false unless public_send("#{column_sym}_changed?")

          old_array = public_send("#{column_sym}_was") || []
          new_array = public_send(column_sym) || []

          # Compare membership, not array equality
          old_value = old_array.is_a?(Array) && old_array.include?(value_to_store)
          new_value = new_array.is_a?(Array) && new_array.include?(value_to_store)

          old_value != new_value
        end

        # Dirty tracking: _was
        model_class.define_method("#{setting_sym}_was") do
          old_array = public_send("#{column_sym}_was") || []
          old_array.is_a?(Array) && old_array.include?(value_to_store)
        end

        # Dirty tracking: _change
        model_class.define_method("#{setting_sym}_change") do
          return nil unless public_send("#{setting_sym}_changed?")

          [public_send("#{setting_sym}_was"), public_send(setting_sym)]
        end

        # Add validation to ensure column is an array
        # Use class instance variable to track which columns have validation
        validated_columns = model_class.instance_variable_get(:@_array_validated_columns) || Set.new
        unless validated_columns.include?(column_sym)
          model_class.validates column_sym, array_type: true
          validated_columns << column_sym
          model_class.instance_variable_set(:@_array_validated_columns, validated_columns)
        end
      end
    end
  end
end
