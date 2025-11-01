# frozen_string_literal: true

module ModelSettings
  module Adapters
    # StoreModel adapter for storing settings in StoreModel attributes
    #
    # Leverages StoreModel gem's built-in dirty tracking for nested JSON structures.
    # This adapter is ideal for complex nested settings that need proper type casting
    # and validation.
    #
    # Requirements:
    # - StoreModel gem must be installed
    # - JSONB column must exist in database (via migration)
    # - StoreModel class must be defined with attributes
    #
    # Features:
    # - Native StoreModel dirty tracking
    # - Type casting and validation
    # - Helper methods (enable!, disable!, toggle!)
    # - Nested attribute support
    #
    # Example migration:
    #   add_column :callcenters, :ai_settings, :jsonb, default: {}, null: false
    #
    # Example StoreModel class:
    #   class AiSettings
    #     include StoreModel::Model
    #     attribute :transcription, :boolean, default: false
    #     attribute :sentiment, :boolean, default: false
    #   end
    #
    # Example usage:
    #   class Callcenter < ApplicationRecord
    #     include ModelSettings::DSL
    #
    #     attribute :ai_settings, AiSettings.to_type
    #
    #     setting :transcription,
    #             type: :store_model,
    #             storage: {column: :ai_settings}
    #   end
    #
    #   callcenter.transcription = true
    #   callcenter.transcription_changed? # => true (via StoreModel)
    class StoreModel < Base
      def setup!
        setting_name = setting.name
        column_name = storage_column
        setting_obj = setting

        # Define accessor that delegates to StoreModel attribute
        model_class.define_method(setting_name) do
          store = public_send(column_name)
          return nil unless store
          store.public_send(setting_name)
        end

        model_class.define_method("#{setting_name}=") do |value|
          store = public_send(column_name)
          return unless store
          store.public_send("#{setting_name}=", value)
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

        # Define before_type_cast method for validator support
        model_class.define_method("#{setting_name}_before_type_cast") do
          store = public_send(column_name)
          return nil unless store
          store.public_send("#{setting_name}_before_type_cast")
        end

        # Add Rails validation to ensure only boolean values (only for non-nested settings)
        # Skip validation if validate: false option is set
        should_validate = setting.options[:validate] != false && !setting.children.any?
        model_class.validates setting_name, boolean_value: true if should_validate

        # Define changed? method using column-level dirty tracking
        model_class.define_method("#{setting_name}_changed?") do
          return false unless public_send("#{column_name}_changed?")

          old_store = public_send("#{column_name}_was")
          new_store = public_send(column_name)

          old_value = old_store&.public_send(setting_name)
          new_value = new_store&.public_send(setting_name)

          old_value != new_value
        end

        # Define _was method using column-level dirty tracking
        model_class.define_method("#{setting_name}_was") do
          old_store = public_send("#{column_name}_was")
          old_store&.public_send(setting_name)
        end

        # Define _change method using column-level dirty tracking
        model_class.define_method("#{setting_name}_change") do
          return nil unless public_send("#{setting_name}_changed?")

          [public_send("#{setting_name}_was"), public_send(setting_name)]
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

      private

      # Get the column name from storage configuration
      def storage_column
        storage = setting.storage
        return storage[:column] if storage.is_a?(Hash) && storage[:column]

        raise ArgumentError, ErrorMessages.adapter_configuration_error(
          :store_model,
          setting,
          @model_class
        )
      end
    end
  end
end
