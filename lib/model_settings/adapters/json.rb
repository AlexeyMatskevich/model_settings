# frozen_string_literal: true

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

        # Setup accessor methods for this setting
        setup_accessors(column_name, setting_name)

        # Define enable! helper method with callbacks
        model_class.define_method("#{setting_name}_enable!") do
          # Execute before_enable callback
          execute_setting_callbacks(setting_obj, :enable, :before)

          # Set the value
          public_send("#{setting_name}=", true)

          # Execute after_enable callback
          execute_setting_callbacks(setting_obj, :enable, :after)

          # Track for after_commit if needed
          track_setting_change_for_commit(setting_obj) if setting_obj.options[:after_change_commit]
        end

        # Define disable! helper method with callbacks
        model_class.define_method("#{setting_name}_disable!") do
          # Execute before_disable callback
          execute_setting_callbacks(setting_obj, :disable, :before)

          # Set the value
          public_send("#{setting_name}=", false)

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

      # Setup accessor methods for a setting within a JSON column
      def setup_accessors(column_name, setting_name)
        column_sym = column_name.to_sym
        setting_sym = setting_name.to_sym
        setting_str = setting_name.to_s

        # Track that we're managing this setting
        add_managed_setting(column_sym, setting_sym)

        # Define getter method
        model_class.define_method(setting_sym) do
          data = public_send(column_sym) || {}
          data[setting_str]
        end

        # Define setter method with dirty tracking
        model_class.define_method("#{setting_sym}=") do |value|
          data = public_send(column_sym) || {}
          data[setting_str] = value
          public_send("#{column_sym}=", data)
        end

        # Define changed? method
        model_class.define_method("#{setting_sym}_changed?") do
          return false unless public_send("#{column_sym}_changed?")

          old_data = public_send("#{column_sym}_was") || {}
          new_data = public_send(column_sym) || {}
          old_data[setting_str] != new_data[setting_str]
        end

        # Define _was method
        model_class.define_method("#{setting_sym}_was") do
          old_data = public_send("#{column_sym}_was") || {}
          old_data[setting_str]
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
          child_name = child_setting.name
          setup_accessors(column_name, child_name)

          # Define helper methods for nested settings with callbacks
          model_class.define_method("#{child_name}_enable!") do
            # Execute before_enable callback
            execute_setting_callbacks(child_setting, :enable, :before)

            # Set the value
            public_send("#{child_name}=", true)

            # Execute after_enable callback
            execute_setting_callbacks(child_setting, :enable, :after)

            # Track for after_commit if needed
            track_setting_change_for_commit(child_setting) if child_setting.options[:after_change_commit]
          end

          model_class.define_method("#{child_name}_disable!") do
            # Execute before_disable callback
            execute_setting_callbacks(child_setting, :disable, :before)

            # Set the value
            public_send("#{child_name}=", false)

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
        end
      end
    end
  end
end
