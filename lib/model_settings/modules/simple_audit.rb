# frozen_string_literal: true

module ModelSettings
  module Modules
    # Simple Audit module demonstrating callback configuration API usage
    #
    # This is a minimal example showing how to:
    # 1. Register callback configuration with default timing
    # 2. Allow users to configure callback timing globally
    # 3. Execute runtime logic at the configured time
    #
    # @example Basic usage
    #   class Account < ApplicationRecord
    #     include ModelSettings::DSL
    #     include ModelSettings::Modules::SimpleAudit
    #
    #     setting :premium_mode,
    #             type: :column,
    #             track_changes: true
    #   end
    #
    # @example Configure callback timing
    #   ModelSettings.configure do |config|
    #     config.module_callback(:simple_audit, :after_commit)
    #   end
    #
    module SimpleAudit
      extend ActiveSupport::Concern

      # Module-level registrations (executed ONCE when module is loaded)

      # 1. Register module
      ModelSettings::ModuleRegistry.register_module(:simple_audit, self)

      # 2. Register DSL option
      ModelSettings::ModuleRegistry.register_option(:track_changes) do |setting, value|
        unless [true, false].include?(value)
          raise ArgumentError, "track_changes must be true or false, got #{value.inspect}"
        end
      end

      # 3. Register callback configuration
      #    - Default: run validation before save
      #    - Configurable: users can change this globally
      ModelSettings::ModuleRegistry.register_module_callback_config(
        :simple_audit,
        default_callback: :before_save,
        configurable: true
      )

      # 4. Compilation-time indexing (registered ONCE, executed for all models)
      ModelSettings::ModuleRegistry.on_settings_compiled do |settings, model_class|
        next unless ModelSettings::ModuleRegistry.module_included?(:simple_audit, model_class)

        # Build index of tracked settings using centralized metadata
        tracked = settings.select { |s| s.get_option(:track_changes) == true }.map(&:name)

        # Store in centralized metadata instead of class_attribute
        ModelSettings::ModuleRegistry.set_module_metadata(
          model_class,
          :simple_audit,
          :tracked_settings,
          tracked
        )
      end

      included do
        # 5. Get the configured callback and register Rails callback (per-class)
        callback_name = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        send(callback_name, :audit_tracked_settings)

        # 6. Add to active modules
        settings_add_module(:simple_audit) if respond_to?(:settings_add_module)
      end

      # Class methods
      module ClassMethods
        # Get all settings with change tracking enabled
        #
        # @return [Array<Setting>] Settings with track_changes: true
        def tracked_settings
          tracked_names = ModelSettings::ModuleRegistry.get_module_metadata(
            self,
            :simple_audit,
            :tracked_settings
          ) || []

          tracked_names.map { |name| find_setting(name) }.compact
        end

        # Check if a setting has change tracking enabled
        #
        # @param setting_name [Symbol] Setting name
        # @return [Boolean]
        def setting_tracked?(setting_name)
          tracked_names = ModelSettings::ModuleRegistry.get_module_metadata(
            self,
            :simple_audit,
            :tracked_settings
          ) || []

          tracked_names.include?(setting_name.to_sym)
        end
      end

      private

      # Audit method that runs at the configured callback time
      #
      # This method executes during the Rails lifecycle at the time
      # configured via ModelSettings.configure (or default: :before_save)
      #
      # @return [void]
      def audit_tracked_settings
        return unless persisted? # Only audit existing records

        self.class.tracked_settings.each do |setting|
          setting_name = setting.name
          next unless respond_to?("#{setting_name}_changed?")
          next unless public_send("#{setting_name}_changed?")

          old_value = public_send("#{setting_name}_was")
          new_value = public_send(setting_name)

          Rails.logger.info(
            "[SimpleAudit] #{self.class.name}##{id} - " \
            "#{setting_name}: #{old_value.inspect} → #{new_value.inspect}"
          )
        end
      end
    end
  end
end
