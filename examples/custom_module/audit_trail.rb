# frozen_string_literal: true

# Example Custom Module: AuditTrail
#
# This module demonstrates all major features of the ModelSettings Module Development API.
# It adds audit logging capabilities to settings, tracking all changes with configurable
# detail levels and user attribution.
#
# Usage:
#   class User < ApplicationRecord
#     include ModelSettings::DSL
#     include ModelSettings::Modules::AuditTrail
#
#     setting :premium,
#       type: :column,
#       audit_level: :detailed,
#       audit_user: ->(user) { Current.user }
#   end
#
# See README.md for complete documentation.

module ModelSettings
  module Modules
    module AuditTrail
      extend ActiveSupport::Concern

      # Model for storing audit logs (you'll need to create this in your app)
      class AuditLog < ActiveRecord::Base
        belongs_to :model, polymorphic: true
        belongs_to :user, optional: true

        validates :setting, presence: true
        validates :level, presence: true, inclusion: {in: %w[minimal detailed]}

        # Serialize values as JSON for complex types
        serialize :old_value, coder: JSON
        serialize :new_value, coder: JSON
      end

      included do
        # ============================================================================
        # STEP 1: Register the Module
        # ============================================================================

        ModuleRegistry.register_module(:audit_trail, self)

        # ============================================================================
        # STEP 2: Register Custom DSL Options
        # ============================================================================

        # Option: audit_level
        # Specifies the detail level for audit logging
        ModuleRegistry.register_option(:audit_level) do |value, setting, model_class|
          unless [:minimal, :detailed].include?(value)
            raise ArgumentError,
              "audit_level must be :minimal or :detailed, got: #{value.inspect}\n\n" \
              "Valid options:\n" \
              "  :minimal - Log only that change occurred\n" \
              "  :detailed - Log old and new values\n\n" \
              "Example:\n" \
              "  setting :premium, audit_level: :detailed"
          end
        end

        # Option: audit_user
        # Callable that returns the user making the change
        ModuleRegistry.register_option(:audit_user) do |value, setting, model_class|
          unless value.nil? || value.respond_to?(:call)
            raise ArgumentError,
              "audit_user must be a callable (Proc/Lambda), got: #{value.class}\n\n" \
              "Example:\n" \
              "  setting :premium, audit_user: ->(instance) { Current.user }\n" \
              "  setting :premium, audit_user: proc { User.current }"
          end
        end

        # Option: audit_if (conditional auditing)
        # Callable that determines whether to audit this change
        ModuleRegistry.register_option(:audit_if) do |value, setting, model_class|
          unless value.nil? || value.respond_to?(:call)
            raise ArgumentError,
              "audit_if must be a callable (Proc/Lambda), got: #{value.class}\n\n" \
              "Example:\n" \
              "  setting :premium, audit_if: ->(instance) { instance.account_type == 'enterprise' }"
          end
        end

        # ============================================================================
        # STEP 3: Register Inheritable Options
        # ============================================================================

        # Make audit_level inheritable so nested settings automatically get audited
        ModuleRegistry.register_inheritable_option(
          :audit_level,
          merge_strategy: :replace, # Child can override parent's level
          auto_include: true # Automatically add to global inheritable options
        )

        # audit_user is also inheritable
        ModuleRegistry.register_inheritable_option(
          :audit_user,
          merge_strategy: :replace,
          auto_include: true
        )

        # ============================================================================
        # STEP 4: Register Callback Configuration
        # ============================================================================

        # Default to :after_save but allow users to change it
        ModuleRegistry.register_module_callback_config(
          :audit_trail,
          default_callback: :after_save,
          configurable: true
        )

        # ============================================================================
        # STEP 5: Register Lifecycle Hooks
        # ============================================================================

        # Hook: on_setting_defined
        # Capture audit configuration when setting is defined
        ModuleRegistry.on_setting_defined do |setting, model_class|
          # Only store metadata if audit_level is specified
          if setting.options[:audit_level]
            metadata = {
              level: setting.options[:audit_level],
              user_callable: setting.options[:audit_user],
              condition: setting.options[:audit_if]
            }

            ModuleRegistry.set_module_metadata(
              model_class,
              :audit_trail,
              setting.name,
              metadata
            )
          end
        end

        # Hook: after_setting_change
        # Create audit log when setting changes
        ModuleRegistry.after_setting_change do |instance, setting, old_value, new_value|
          # Get audit configuration for this setting
          meta = ModuleRegistry.get_module_metadata(
            instance.class,
            :audit_trail,
            setting.name
          )

          # Skip if not audited
          next unless meta

          # Check conditional auditing
          if meta[:condition]
            should_audit = begin
              meta[:condition].call(instance)
            rescue => e
              Rails.logger.warn "AuditTrail: audit_if condition failed: #{e.message}"
              false
            end
            next unless should_audit
          end

          # Get user if specified
          user = if meta[:user_callable]
            begin
              meta[:user_callable].call(instance)
            rescue => e
              Rails.logger.warn "AuditTrail: audit_user callable failed: #{e.message}"
              nil
            end
          end

          # Determine what to log based on level
          log_data = case meta[:level]
          when :minimal
            {
              model: instance,
              setting: setting.name.to_s,
              old_value: nil, # Don't log actual values
              new_value: nil,
              level: "minimal",
              user: user
            }
          when :detailed
            {
              model: instance,
              setting: setting.name.to_s,
              old_value: old_value,
              new_value: new_value,
              level: "detailed",
              user: user
            }
          end

          # Create audit log
          begin
            AuditLog.create!(log_data)
          rescue => e
            Rails.logger.error "AuditTrail: Failed to create audit log: #{e.message}"
            # Don't raise - audit failure shouldn't break the app
          end
        end

        # ============================================================================
        # STEP 6: Register Query Methods (for introspection)
        # ============================================================================

        ModuleRegistry.register_query_method(
          :audit_trail,
          :audited_settings,
          :class,
          description: "Returns all settings that are being audited",
          returns: "Array<Setting>",
          example: "User.audited_settings  # => [#<Setting name=:premium>]"
        )

        ModuleRegistry.register_query_method(
          :audit_trail,
          :audit_history,
          :instance,
          description: "Returns audit history for a specific setting",
          parameters: [{name: :setting_name, type: :symbol}],
          returns: "ActiveRecord::Relation<AuditLog>",
          example: "user.audit_history(:premium)  # => [#<AuditLog...>]"
        )
      end

      # ============================================================================
      # STEP 7: Add Class Methods
      # ============================================================================

      class_methods do
        # Get all settings that have audit_level configured
        #
        # @return [Array<Setting>] Settings being audited
        #
        # @example
        #   User.audited_settings
        #   # => [#<Setting name=:premium>, #<Setting name=:billing>]
        def audited_settings
          settings.select do |setting|
            ModuleRegistry.module_metadata?(self, :audit_trail, setting.name)
          end
        end

        # Get audit configuration for a specific setting
        #
        # @param setting_name [Symbol] Setting name
        # @return [Hash, nil] Audit configuration or nil
        #
        # @example
        #   User.audit_config_for(:premium)
        #   # => {level: :detailed, user_callable: #<Proc...>}
        def audit_config_for(setting_name)
          ModuleRegistry.get_module_metadata(self, :audit_trail, setting_name)
        end
      end

      # ============================================================================
      # STEP 8: Add Instance Methods
      # ============================================================================

      # Get audit history for a specific setting
      #
      # @param setting_name [Symbol] Setting name
      # @return [ActiveRecord::Relation<AuditLog>] Audit logs
      #
      # @example
      #   user.audit_history(:premium)
      #   # => [#<AuditLog old_value: false, new_value: true, created_at: ...>]
      def audit_history(setting_name)
        AuditLog.where(
          model: self,
          setting: setting_name.to_s
        ).order(created_at: :desc)
      end

      # Get all audit logs for this model instance
      #
      # @return [ActiveRecord::Relation<AuditLog>] All audit logs
      #
      # @example
      #   user.all_audit_logs
      #   # => [#<AuditLog setting: "premium", ...>, #<AuditLog setting: "billing", ...>]
      def all_audit_logs
        AuditLog.where(model: self).order(created_at: :desc)
      end

      # Check if a setting is being audited
      #
      # @param setting_name [Symbol] Setting name
      # @return [Boolean] True if setting is audited
      #
      # @example
      #   user.audited?(:premium)  # => true
      #   user.audited?(:unknown)  # => false
      def audited?(setting_name)
        ModuleRegistry.module_metadata?(self.class, :audit_trail, setting_name)
      end
    end
  end
end
