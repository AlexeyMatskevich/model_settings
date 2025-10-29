# frozen_string_literal: true

module ModelSettings
  module Adapters
    # Column adapter for simple boolean columns
    #
    # Uses standard ActiveRecord columns with native dirty tracking.
    # This is the simplest and most performant adapter.
    #
    # Requirements:
    # - Column must exist in database (via migration)
    # - Column should be boolean type (but can be other types)
    #
    # Features:
    # - Native Rails dirty tracking (column_name_changed?, column_name_was, etc.)
    # - Helper methods (enable!, disable!, toggle!)
    # - No additional configuration needed
    #
    # Example migration:
    #   add_column :users, :notifications_enabled, :boolean, default: false, null: false
    #
    # Example usage:
    #   class User < ApplicationRecord
    #     include ModelSettings::DSL
    #
    #     setting :notifications_enabled, type: :column, default: false
    #   end
    #
    #   user.notifications_enabled = true
    #   user.notifications_enabled_changed? # => true
    #   user.notifications_enabled_was      # => false
    #   user.notifications_enabled_enable!  # Helper method
    class Column < Base
      def setup!
        setting_name = setting.name
        setting_obj = setting

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
          public_send("#{setting_name}=", !public_send(setting_name))

          # Execute after_toggle callback
          execute_setting_callbacks(setting_obj, :toggle, :after)

          # Track for after_commit if needed
          track_setting_change_for_commit(setting_obj) if setting_obj.options[:after_change_commit]
        end

        # Define enabled? helper (alias for the attribute itself for boolean settings)
        model_class.define_method("#{setting_name}_enabled?") do
          !!public_send(setting_name)
        end

        # Define disabled? helper
        model_class.define_method("#{setting_name}_disabled?") do
          !public_send(setting_name)
        end
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
    end
  end
end
