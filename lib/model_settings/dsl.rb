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
      # Store all settings defined on this model
      class_attribute :_settings, default: []

      # Store settings by name for quick lookup
      class_attribute :_settings_by_name, default: {}
    end

    class_methods do
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
        # Create Setting object
        parent_setting = @_current_setting_context
        setting_obj = Setting.new(name, options, parent: parent_setting)

        # Add to parent or root collection
        if parent_setting
          parent_setting.add_child(setting_obj)
        else
          self._settings = _settings + [setting_obj]
          self._settings_by_name = _settings_by_name.merge(name => setting_obj)
        end

        # Process nested settings if block given
        if block_given?
          previous_context = @_current_setting_context
          @_current_setting_context = setting_obj
          instance_eval(&block)
          @_current_setting_context = previous_context
        end

        # Setup storage adapter for this setting (only for root settings)
        if !parent_setting
          adapter = create_adapter_for(setting_obj)
          adapter.setup!
        end

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
          # Will be implemented in Sprint 2
          raise NotImplementedError, "JSON adapter not yet implemented"
        when :store_model
          # Will be implemented in Sprint 2
          raise NotImplementedError, "StoreModel adapter not yet implemented"
        else
          raise ArgumentError, "Unknown storage type: #{setting.type}"
        end

        adapter_class.new(self, setting)
      end

      # Get all settings defined on this model
      #
      # @return [Array<Setting>] Array of Setting objects
      def settings
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

      private

      # Track current setting context for nested definitions
      attr_accessor :_current_setting_context
    end
  end
end
