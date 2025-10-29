# frozen_string_literal: true

module ModelSettings
  # Deprecation tracking for settings
  #
  # Provides warnings and tracking for deprecated settings.
  # Helps with migration workflows for phased rollouts.
  #
  # Usage:
  #   setting :old_feature,
  #           deprecated: "Use new_feature instead",
  #           deprecated_since: "2.0.0"
  #
  module Deprecation
    extend ActiveSupport::Concern

    included do
      # Track deprecated setting usage (only for ActiveRecord models)
      if respond_to?(:after_initialize)
        after_initialize :warn_about_deprecated_settings, if: -> { self.class.respond_to?(:deprecated_settings) }
      end
    end

    module ClassMethods
      # Get all deprecated settings
      #
      # @return [Array<Setting>] Deprecated settings
      def deprecated_settings
        all_settings_recursive.select(&:deprecated?)
      end

      # Get settings deprecated since a specific version
      #
      # @param version [String] Version string
      # @return [Array<Setting>] Settings deprecated since version
      def settings_deprecated_since(version)
        deprecated_settings.select do |setting|
          since = setting.metadata[:deprecated_since]
          since && since >= version
        end
      end

      # Check if a setting is deprecated
      #
      # @param setting_name [Symbol] Setting name
      # @return [Boolean]
      def setting_deprecated?(setting_name)
        setting = find_setting(setting_name)
        setting&.deprecated? || false
      end

      # Get deprecation reason for a setting
      #
      # @param setting_name [Symbol] Setting name
      # @return [String, nil] Deprecation reason
      def deprecation_reason_for(setting_name)
        setting = find_setting(setting_name)
        setting&.deprecation_reason
      end

      # Generate deprecation report
      #
      # @return [Hash] Report with deprecated settings info
      def deprecation_report
        deprecated = deprecated_settings

        {
          total_count: deprecated.size,
          settings: deprecated.map do |setting|
            {
              name: setting.name,
              path: setting.path,
              reason: setting.deprecation_reason,
              since: setting.metadata[:deprecated_since],
              replacement: setting.metadata[:replacement]
            }
          end,
          by_version: deprecated.group_by { |s| s.metadata[:deprecated_since] || "unknown" }
        }
      end
    end

    # Warn about deprecated settings that are enabled
    def warn_about_deprecated_settings
      self.class.deprecated_settings.each do |setting|
        next unless respond_to?(setting.name)

        value = public_send(setting.name)
        next unless value # Only warn if setting is enabled/set

        warn_deprecated_setting(setting)
      end
    end

    # Warn about a specific deprecated setting
    #
    # @param setting [Setting] The deprecated setting
    def warn_deprecated_setting(setting)
      message = "DEPRECATION WARNING: Setting '#{setting.name}' is deprecated"

      if setting.metadata[:deprecated_since]
        message += " since version #{setting.metadata[:deprecated_since]}"
      end

      message += ". #{setting.deprecation_reason}" if setting.deprecation_reason

      if setting.metadata[:replacement]
        message += " Please use '#{setting.metadata[:replacement]}' instead."
      end

      # Use Rails logger if available, otherwise warn
      if defined?(Rails) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end

      # Track deprecation usage (could be sent to metrics service)
      track_deprecated_setting_usage(setting)
    end

    # Track deprecated setting usage for metrics
    #
    # @param setting [Setting] The deprecated setting
    def track_deprecated_setting_usage(setting)
      # Hook for metrics tracking
      # Override this method in your application to send to your metrics service
      # Example:
      #   Metrics.increment("deprecated_setting.#{setting.name}")
    end

    # Check if any deprecated settings are in use
    #
    # @return [Boolean]
    def using_deprecated_settings?
      self.class.deprecated_settings.any? do |setting|
        next unless respond_to?(setting.name)
        !!public_send(setting.name)
      end
    end

    # Get list of deprecated settings currently in use
    #
    # @return [Array<Symbol>] Setting names
    def active_deprecated_settings
      self.class.deprecated_settings.filter_map do |setting|
        next unless respond_to?(setting.name)
        setting.name if public_send(setting.name)
      end
    end
  end
end
