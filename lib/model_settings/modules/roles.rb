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

      # Register query methods for introspection
      ModelSettings::ModuleRegistry.register_query_method(
        :roles, :settings_viewable_by, :class,
        description: "Get all settings viewable by a specific role",
        parameters: {role: :Symbol},
        returns: "Array<Symbol>"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :roles, :settings_editable_by, :class,
        description: "Get all settings editable by a specific role",
        parameters: {role: :Symbol},
        returns: "Array<Symbol>"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :roles, :can_view_setting?, :instance,
        description: "Check if a setting is viewable by a specific role",
        parameters: {setting_name: :Symbol, role: :Symbol},
        returns: "Boolean"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :roles, :can_edit_setting?, :instance,
        description: "Check if a setting is editable by a specific role",
        parameters: {setting_name: :Symbol, role: :Symbol},
        returns: "Boolean"
      )

      # Register viewable_by option
      ModelSettings::ModuleRegistry.register_option(:viewable_by) do |value, setting, model_class|
        unless value == :all || value.is_a?(Array) || value.is_a?(Symbol)
          raise ArgumentError,
            "viewable_by must be :all, a Symbol, or an Array of Symbols " \
            "(got #{value.class}). " \
            "Example: viewable_by: [:admin, :manager] or viewable_by: :all"
        end
      end

      # Register editable_by option
      ModelSettings::ModuleRegistry.register_option(:editable_by) do |value, setting, model_class|
        unless value == :all || value.is_a?(Array) || value.is_a?(Symbol)
          raise ArgumentError,
            "editable_by must be :all, a Symbol, or an Array of Symbols " \
            "(got #{value.class}). " \
            "Example: editable_by: [:admin] or editable_by: :all"
        end
      end

      # Register role options as inheritable with :append strategy
      # This allows child settings to inherit and extend parent roles
      # Example: parent viewable_by: [:admin], child viewable_by: [:manager]
      #          => child inherits [:admin, :manager]
      ModelSettings::ModuleRegistry.register_inheritable_option(
        :viewable_by,
        merge_strategy: :append
      )
      ModelSettings::ModuleRegistry.register_inheritable_option(
        :editable_by,
        merge_strategy: :append
      )

      # Register inherit_authorization option
      ModelSettings::ModuleRegistry.register_option(:inherit_authorization) do |value, setting, model_class|
        valid_values = [true, false, :view_only, :edit_only]
        unless valid_values.include?(value)
          raise ArgumentError,
            "inherit_authorization must be one of: #{valid_values.join(", ")} " \
            "(got #{value.inspect}). " \
            "Examples:\n" \
            "  inherit_authorization: true       # Inherit both view and edit\n" \
            "  inherit_authorization: :view_only # Inherit only view permissions\n" \
            "  inherit_authorization: :edit_only # Inherit only edit permissions\n" \
            "  inherit_authorization: false      # Don't inherit"
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
        settings_check_exclusive_conflict!(:roles) if respond_to?(:settings_check_exclusive_conflict!)
      end

      module ClassMethods
        # Resolve authorization using 5-level priority system
        #
        # Priority (highest to lowest):
        # 1. Explicit setting value (not :inherit)
        # 2. Explicit :inherit keyword
        # 3. Setting inherit_authorization option
        # 4. Model settings_config
        # 5. Global configuration
        #
        # @param setting [ModelSettings::Setting] The setting to resolve authorization for
        # @param aspect [Symbol] Authorization aspect (:viewable_by or :editable_by)
        # @param visited [Set] Set of visited settings (for cycle detection)
        # @return [Array<Symbol>, Symbol, nil] Resolved roles array, :all, or nil
        #
        def resolve_authorization_with_priority(setting, aspect, visited = Set.new)
          # Level 1: Explicit setting value (not nil, not :inherit)
          explicit = setting.options[aspect]
          return normalize_roles(explicit) if explicit.present? && explicit != :inherit

          # Level 2: Explicit :inherit keyword
          return resolve_from_parent(setting, aspect, visited) if explicit == :inherit

          # Level 3: Setting inherit_authorization option
          if setting.options.key?(:inherit_authorization)
            inherit_option = setting.options[:inherit_authorization]
            case inherit_option
            when true
              return resolve_from_parent(setting, aspect, visited)
            when :view_only
              # :view_only: inherit only viewable_by, not editable_by
              return (aspect == :viewable_by) ? resolve_from_parent(setting, aspect, visited) : nil
            when :edit_only
              # :edit_only: inherit only editable_by, not viewable_by
              return (aspect == :editable_by) ? resolve_from_parent(setting, aspect, visited) : nil
            when false
              # Explicitly disabled
              return nil
            end
          end

          # Level 4: Model-level configuration
          model_config = settings_config_value(:inherit_authorization) if respond_to?(:settings_config_value, true)
          if model_config
            case model_config
            when true
              return resolve_from_parent(setting, aspect, visited)
            when :view_only
              return (aspect == :viewable_by) ? resolve_from_parent(setting, aspect, visited) : nil
            when :edit_only
              return (aspect == :editable_by) ? resolve_from_parent(setting, aspect, visited) : nil
            when false
              return nil
            end
          end

          # Level 5: Global configuration
          if ModelSettings.configuration.respond_to?(:inherit_authorization)
            global_config = ModelSettings.configuration.inherit_authorization
            case global_config
            when true
              return resolve_from_parent(setting, aspect, visited)
            when :view_only
              return resolve_from_parent(setting, aspect, visited) if aspect == :viewable_by
            when :edit_only
              return resolve_from_parent(setting, aspect, visited) if aspect == :editable_by
            end
          end

          # No inheritance - return nil (no authorization)
          nil
        end

        # Resolve authorization from parent setting
        #
        # Recursively walks up the setting tree to find authorization.
        # Includes cycle detection to prevent infinite loops.
        #
        # @param setting [ModelSettings::Setting] The setting
        # @param aspect [Symbol] Authorization aspect (:viewable_by or :editable_by)
        # @param visited [Set] Set of visited settings (for cycle detection)
        # @return [Array<Symbol>, Symbol, nil] Resolved roles, or nil if no parent
        #
        # @raise [ArgumentError] If circular reference detected
        #
        def resolve_from_parent(setting, aspect, visited)
          # Cycle detection
          if visited.include?(setting.name)
            cycle_path = visited.to_a.join(" -> ")
            raise ArgumentError,
              "Circular authorization inheritance detected: #{cycle_path} -> #{setting.name}"
          end

          visited = visited.dup.add(setting.name)
          parent = setting.parent
          return nil unless parent # No parent = no authorization

          # Recursively resolve parent's authorization
          resolve_authorization_with_priority(parent, aspect, visited)
        end

        # Normalize roles value to consistent format
        #
        # @param value [Symbol, Array, nil] Role value
        # @return [Symbol, Array<Symbol>, nil] Normalized value
        #
        def normalize_roles(value)
          return :all if value == :all
          return nil if value.nil?
          Array(value).map(&:to_sym)
        end

        # Find setting by name (utility method)
        #
        # @param name [Symbol] Setting name
        # @return [ModelSettings::Setting, nil] Setting object or nil if not found
        #
        def find_setting_by_name(name)
          all_settings_recursive.find { |s| s.name == name }
        end

        # Get all settings viewable by a specific role (with inheritance)
        #
        # Returns only settings with explicit authorization (not unrestricted settings).
        #
        # @param role [Symbol] Role name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_viewable_by(:manager)
        #   # => [:billing_override, :display_name]
        #
        def settings_viewable_by(role)
          all_settings_recursive.select do |setting|
            roles = resolve_authorization_with_priority(setting, :viewable_by)
            # Only include settings with explicit authorization
            # nil = no restriction (not included)
            # :all = explicitly viewable by all (included)
            # Array = viewable by specific roles (included if role matches)
            roles && (roles == :all || roles.include?(role.to_sym))
          end.map(&:name)
        end

        # Get all settings editable by a specific role (with inheritance)
        #
        # Returns only settings with explicit authorization (not unrestricted settings).
        #
        # @param role [Symbol] Role name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_editable_by(:finance)
        #   # => [:billing_override]
        #
        def settings_editable_by(role)
          all_settings_recursive.select do |setting|
            roles = resolve_authorization_with_priority(setting, :editable_by)
            # Only include settings with explicit authorization
            # nil = no restriction (not included)
            # :all = explicitly editable by all (included)
            # Array = editable by specific roles (included if role matches)
            roles && (roles == :all || roles.include?(role.to_sym))
          end.map(&:name)
        end
      end

      # Instance Methods

      # Check if a setting is viewable by a specific role (with inheritance)
      #
      # @param setting_name [Symbol] Setting name
      # @param role [Symbol] Role name
      # @return [Boolean]
      #
      # @example
      #   user.can_view_setting?(:billing_override, :manager)
      #   # => true
      #
      # @example With inheritance
      #   user.can_view_setting?(:nested_child, :admin)
      #   # => true (inherited from parent)
      #
      def can_view_setting?(setting_name, role)
        setting = self.class.find_setting_by_name(setting_name)
        return true unless setting # Setting not found = viewable

        roles = self.class.resolve_authorization_with_priority(setting, :viewable_by)
        return true if roles.nil? # No restriction = viewable

        roles == :all || roles.include?(role.to_sym)
      end

      # Check if a setting is editable by a specific role (with inheritance)
      #
      # @param setting_name [Symbol] Setting name
      # @param role [Symbol] Role name
      # @return [Boolean]
      #
      # @example
      #   user.can_edit_setting?(:billing_override, :finance)
      #   # => true
      #
      # @example With inheritance
      #   user.can_edit_setting?(:nested_child, :admin)
      #   # => true (inherited from parent)
      #
      def can_edit_setting?(setting_name, role)
        setting = self.class.find_setting_by_name(setting_name)
        return true unless setting # Setting not found = editable

        roles = self.class.resolve_authorization_with_priority(setting, :editable_by)
        return true if roles.nil? # No restriction = editable

        roles.include?(role.to_sym)
      end
    end
  end
end
