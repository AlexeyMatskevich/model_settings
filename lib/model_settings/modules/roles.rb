# frozen_string_literal: true

module ModelSettings
  module Modules
    # Role-based authorization module for settings
    #
    # This module provides simple role-based access control (RBAC) for settings
    # without requiring a full authorization framework like Pundit or ActionPolicy.
    #
    # IMPORTANT: This module is mutually exclusive with Pundit and ActionPolicy modules.
    # You can only use ONE authorization module at a time.
    #
    # @example Basic usage
    #   class User < ApplicationRecord
    #     include ModelSettings::DSL
    #     include ModelSettings::Modules::Roles
    #
    #     setting :billing_override,
    #             viewable_by: [:admin, :finance, :manager],
    #             editable_by: [:admin, :finance]
    #   end
    #
    # @example With inheritance
    #   class User < ApplicationRecord
    #     setting :billing,
    #             viewable_by: [:admin, :finance],
    #             editable_by: [:admin] do
    #       setting :invoices  # Inherits parent roles
    #     end
    #   end
    #
    module Roles
      extend ActiveSupport::Concern

      # Module-level registrations (executed ONCE when module is loaded)

      # Register module
      ModelSettings::ModuleRegistry.register_module(:roles, self)

      # Register as part of exclusive authorization group
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :roles)

      # Register viewable_by option
      ModelSettings::ModuleRegistry.register_option(:viewable_by) do |setting, value|
        unless value == :all || value.is_a?(Array) || value.is_a?(Symbol)
          raise ArgumentError,
            "viewable_by must be :all, a Symbol, or an Array of Symbols " \
            "(got #{value.class}). " \
            "Example: viewable_by: [:admin, :manager] or viewable_by: :all"
        end
      end

      # Register editable_by option
      ModelSettings::ModuleRegistry.register_option(:editable_by) do |setting, value|
        unless value == :all || value.is_a?(Array) || value.is_a?(Symbol)
          raise ArgumentError,
            "editable_by must be :all, a Symbol, or an Array of Symbols " \
            "(got #{value.class}). " \
            "Example: editable_by: [:admin] or editable_by: :all"
        end
      end

      # Hook to capture role metadata when settings are defined
      ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
        next unless ModelSettings::ModuleRegistry.module_included?(:roles, model_class)

        if setting.options.key?(:viewable_by) || setting.options.key?(:editable_by)
          # Normalize roles helper (inline)
          normalize = ->(value) {
            return :all if value == :all
            return [] if value.nil?
            Array(value).map(&:to_sym)
          }

          metadata = {
            viewable_by: normalize.call(setting.options[:viewable_by]),
            editable_by: normalize.call(setting.options[:editable_by])
          }

          ModelSettings::ModuleRegistry.set_module_metadata(
            model_class,
            :roles,
            setting.name,
            metadata
          )
        end
      end

      included do
        # Add to active modules FIRST (before conflict check)
        settings_add_module(:roles) if respond_to?(:settings_add_module)

        # Check for conflicts with other authorization modules
        ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :roles)
      end

      module ClassMethods
        # Get all settings viewable by a specific role
        #
        # @param role [Symbol] Role name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_viewable_by(:manager)
        #   # => [:billing_override, :display_name]
        #
        def settings_viewable_by(role)
          all_roles = ModelSettings::ModuleRegistry.get_module_metadata(self, :roles)

          all_roles.select do |_name, roles|
            roles[:viewable_by] == :all || roles[:viewable_by].include?(role.to_sym)
          end.keys
        end

        # Get all settings editable by a specific role
        #
        # @param role [Symbol] Role name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_editable_by(:finance)
        #   # => [:billing_override]
        #
        def settings_editable_by(role)
          all_roles = ModelSettings::ModuleRegistry.get_module_metadata(self, :roles)

          all_roles.select do |_name, roles|
            roles[:editable_by].include?(role.to_sym)
          end.keys
        end
      end

      # Instance Methods

      # Check if a setting is viewable by a specific role
      #
      # @param setting_name [Symbol] Setting name
      # @param role [Symbol] Role name
      # @return [Boolean]
      #
      # @example
      #   user.can_view_setting?(:billing_override, :manager)
      #   # => true
      #
      def can_view_setting?(setting_name, role)
        roles = ModelSettings::ModuleRegistry.get_module_metadata(
          self.class,
          :roles,
          setting_name
        )
        return true unless roles # No restriction = viewable

        roles[:viewable_by] == :all || roles[:viewable_by].include?(role.to_sym)
      end

      # Check if a setting is editable by a specific role
      #
      # @param setting_name [Symbol] Setting name
      # @param role [Symbol] Role name
      # @return [Boolean]
      #
      # @example
      #   user.can_edit_setting?(:billing_override, :finance)
      #   # => true
      #
      def can_edit_setting?(setting_name, role)
        roles = ModelSettings::ModuleRegistry.get_module_metadata(
          self.class,
          :roles,
          setting_name
        )
        return true unless roles # No restriction = editable

        roles[:editable_by].include?(role.to_sym)
      end
    end
  end
end
