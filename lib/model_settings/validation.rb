# frozen_string_literal: true

require "active_support/concern"
require "active_model"

module ModelSettings
  # Validation module for settings
  #
  # Provides validation capabilities for settings using custom validators.
  # Validators are only triggered when explicitly instantiated or when
  # enable!/disable! methods are called with validation.
  #
  # Usage:
  #   setting :premium_mode,
  #           validate_with: :check_subscription_active
  #
  #   setting :api_access,
  #           validate_with: [:check_api_quota, :check_api_permissions]
  #
  #   # Custom validator
  #   def check_subscription_active
  #     errors.add(:premium_mode, "requires active subscription") unless subscription_active?
  #   end
  module Validation
    extend ActiveSupport::Concern

    included do
      # Initialize errors collection
      attr_reader :setting_errors

      # Set up after_initialize callback (only for ActiveRecord models)
      if respond_to?(:after_initialize)
        after_initialize :initialize_setting_errors
      end
    end

    # Initialize setting errors collection
    def initialize_setting_errors
      @setting_errors ||= ActiveModel::Errors.new(self)
    end

    # Validate a specific setting
    #
    # @param setting_name [Symbol] The setting to validate
    # @param value [Object] The proposed value (nil to use current value)
    # @return [Boolean] true if valid
    def validate_setting(setting_name, value = nil)
      setting = self.class.find_setting(setting_name)
      return true unless setting

      validator = setting.options[:validate_with]
      return true unless validator

      # Clear previous errors for this setting
      @setting_errors.delete(setting_name)

      # Get the value to validate
      value_to_validate = value.nil? ? public_send(setting_name) : value

      # Store temporarily for validator access
      @_validating_setting = setting_name
      @_validating_value = value_to_validate

      # Run the validator(s)
      case validator
      when Symbol
        public_send(validator)
      when Proc
        instance_exec(&validator)
      when Array
        validator.each do |v|
          case v
          when Symbol
            public_send(v)
          when Proc
            instance_exec(&v)
          end
        end
      end

      # Clean up temporary state
      @_validating_setting = nil
      @_validating_value = nil

      # Return true if no errors were added
      !@setting_errors.added?(setting_name, :invalid)
    end

    # Validate all settings
    #
    # @return [Boolean] true if all settings are valid
    def validate_all_settings
      valid = true

      self.class.all_settings_recursive.each do |setting|
        next unless setting.options[:validate_with]

        unless validate_setting(setting.name)
          valid = false
        end
      end

      valid
    end

    # Check if a specific setting is valid
    #
    # @param setting_name [Symbol] The setting to check
    # @return [Boolean]
    def setting_valid?(setting_name)
      !@setting_errors.include?(setting_name)
    end

    # Add a validation error for a setting
    #
    # @param setting_name [Symbol] The setting
    # @param message [String] Error message
    def add_setting_error(setting_name, message)
      @setting_errors.add(setting_name, message)
    end

    # Get validation errors for a setting
    #
    # @param setting_name [Symbol] The setting
    # @return [Array<String>] Array of error messages
    def setting_errors_for(setting_name)
      @setting_errors.where(setting_name).map(&:full_message)
    end

    # Check if setting has any validation errors
    #
    # @param setting_name [Symbol] The setting
    # @return [Boolean]
    def setting_has_errors?(setting_name)
      @setting_errors.where(setting_name).any?
    end

    module ClassMethods
      # Configure validation for settings
      #
      # @param options [Hash] Validation options
      def configure_setting_validation(**options)
        @setting_validation_options = options
      end

      # Get validation configuration
      #
      # @return [Hash]
      def setting_validation_options
        @setting_validation_options || {}
      end
    end
  end
end
