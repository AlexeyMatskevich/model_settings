# frozen_string_literal: true

module ModelSettings
  module Modules
    # I18n module for settings localization
    #
    # Provides internationalization support for settings labels,
    # descriptions, and other text content.
    #
    # Translation keys follow the pattern:
    #   model_settings.{model_name}.{setting_name}.label
    #   model_settings.{model_name}.{setting_name}.description
    #
    # Usage:
    #   setting :notifications_enabled,
    #           i18n: {
    #             label_key: "settings.notifications.label",
    #             description_key: "settings.notifications.description"
    #           }
    #
    # YAML example:
    #   en:
    #     model_settings:
    #       user:
    #         notifications_enabled:
    #           label: "Enable Notifications"
    #           description: "Receive email notifications"
    #
    module I18n
      extend ActiveSupport::Concern

      # Module-level registrations (executed ONCE when module is loaded)

      # Register module
      ModelSettings::ModuleRegistry.register_module(:i18n, self)

      # Register i18n option (metadata for translations)
      ModelSettings::ModuleRegistry.register_option(:i18n) do |setting, value|
        unless value.is_a?(Hash)
          raise ArgumentError,
            "i18n option must be a Hash with translation keys " \
            "(got #{value.class}). " \
            "Example: i18n: { label_key: 'settings.label', description_key: 'settings.desc' }"
        end
      end

      # Register query methods for introspection
      ModelSettings::ModuleRegistry.register_query_method(
        :i18n, :settings_i18n_scope, :class,
        description: "Get default I18n scope for this model",
        returns: "String"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :i18n, :settings_with_i18n, :class,
        description: "Get all settings with I18n metadata",
        returns: "Array<Setting>"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :i18n, :t_label_for, :instance,
        description: "Get translated label for a setting",
        parameters: {setting_name: :Symbol, options: :Hash},
        returns: "String"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :i18n, :t_description_for, :instance,
        description: "Get translated description for a setting",
        parameters: {setting_name: :Symbol, options: :Hash},
        returns: "String, nil"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :i18n, :t_help_for, :instance,
        description: "Get translated help text for a setting",
        parameters: {setting_name: :Symbol, options: :Hash},
        returns: "String, nil"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :i18n, :translations_for, :instance,
        description: "Get all translations for a setting",
        parameters: {setting_name: :Symbol, options: :Hash},
        returns: "Hash"
      )

      included do
        # Add to active modules (if DSL is included)
        settings_add_module(:i18n) if respond_to?(:settings_add_module)
      end

      module ClassMethods
        # Get default I18n scope for this model
        #
        # @return [String] I18n scope
        def settings_i18n_scope
          "model_settings.#{model_name.i18n_key}"
        end

        # Get all settings with I18n metadata
        #
        # @return [Array<Setting>] Settings with I18n configuration
        def settings_with_i18n
          all_settings_recursive.select { |s| s.metadata[:i18n].present? }
        end
      end

      # Get translated label for a setting
      #
      # @param setting_name [Symbol] Setting name
      # @param options [Hash] I18n options (locale, default, etc.)
      # @return [String] Translated label
      def t_label_for(setting_name, **options)
        setting = self.class.find_setting(setting_name)
        return setting_name.to_s.humanize unless setting

        # Check for custom key in metadata
        custom_key = setting.metadata.dig(:i18n, :label_key)
        if custom_key
          return ::I18n.t(custom_key, **options) if defined?(::I18n)
        end

        # Use default scope
        default_key = "#{self.class.settings_i18n_scope}.#{setting_name}.label"
        if defined?(::I18n)
          ::I18n.t(default_key, default: setting_name.to_s.humanize, **options)
        else
          setting_name.to_s.humanize
        end
      end

      # Get translated description for a setting
      #
      # @param setting_name [Symbol] Setting name
      # @param options [Hash] I18n options
      # @return [String, nil] Translated description
      def t_description_for(setting_name, **options)
        setting = self.class.find_setting(setting_name)
        return nil unless setting

        # Check for custom key in metadata
        custom_key = setting.metadata.dig(:i18n, :description_key)
        if custom_key
          return ::I18n.t(custom_key, **options) if defined?(::I18n)
        end

        # Use default scope
        default_key = "#{self.class.settings_i18n_scope}.#{setting_name}.description"
        if defined?(::I18n)
          ::I18n.t(default_key, default: setting.description, **options)
        else
          setting.description
        end
      end

      # Get translated help text for a setting
      #
      # @param setting_name [Symbol] Setting name
      # @param options [Hash] I18n options
      # @return [String, nil] Translated help text
      def t_help_for(setting_name, **options)
        setting = self.class.find_setting(setting_name)
        return nil unless setting

        # Check for custom key in metadata
        custom_key = setting.metadata.dig(:i18n, :help_key)
        if custom_key
          return ::I18n.t(custom_key, **options) if defined?(::I18n)
        end

        # Use default scope
        default_key = "#{self.class.settings_i18n_scope}.#{setting_name}.help"
        if defined?(::I18n)
          ::I18n.t(default_key, default: nil, **options)
        end
      end

      # Get all translations for a setting
      #
      # @param setting_name [Symbol] Setting name
      # @param options [Hash] I18n options
      # @return [Hash] Hash with :label, :description, :help keys
      def translations_for(setting_name, **options)
        {
          label: t_label_for(setting_name, **options),
          description: t_description_for(setting_name, **options),
          help: t_help_for(setting_name, **options)
        }
      end
    end
  end
end
