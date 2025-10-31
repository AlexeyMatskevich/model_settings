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

      included do
        # Check for conflicts with other authorization modules
        ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :roles)

        # Storage for role metadata
        class_attribute :_settings_roles, default: {}
      end

      module ClassMethods
        # Override setting method to capture role options
        #
        # @param name [Symbol] Setting name
        # @param options [Hash] Setting options
        # @option options [Symbol, Array<Symbol>] :viewable_by Roles that can view this setting
        # @option options [Array<Symbol>] :editable_by Roles that can edit this setting
        #
        def setting(name, **options, &block)
          # Extract and store role options
          if options.key?(:viewable_by) || options.key?(:editable_by)
            _settings_roles[name] = {
              viewable_by: normalize_roles(options.delete(:viewable_by)),
              editable_by: normalize_roles(options.delete(:editable_by))
            }
          end

          super
        end

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
          _settings_roles.select do |_name, roles|
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
          _settings_roles.select do |_name, roles|
            roles[:editable_by].include?(role.to_sym)
          end.keys
        end

        private

        # Normalize role values to consistent format
        #
        # @param value [Symbol, Array, nil] Raw role value
        # @return [Symbol, Array<Symbol>] Normalized roles
        #
        def normalize_roles(value)
          return :all if value == :all
          return [] if value.nil?
          Array(value).map(&:to_sym)
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
        roles = self.class._settings_roles[setting_name]
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
        roles = self.class._settings_roles[setting_name]
        return true unless roles # No restriction = editable

        roles[:editable_by].include?(role.to_sym)
      end
    end
  end
end
