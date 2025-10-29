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

        # Define enable! helper method
        model_class.define_method("#{setting_name}_enable!") do
          public_send("#{setting_name}=", true)
        end

        # Define disable! helper method
        model_class.define_method("#{setting_name}_disable!") do
          public_send("#{setting_name}=", false)
        end

        # Define toggle! helper method
        model_class.define_method("#{setting_name}_toggle!") do
          public_send("#{setting_name}=", !public_send(setting_name))
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
