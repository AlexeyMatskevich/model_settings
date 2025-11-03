# frozen_string_literal: true

module ModelSettings
  module Modules
    # Base module for policy-based authorization (Pundit, ActionPolicy)
    #
    # This module provides complete shared functionality for policy-based authorization modules:
    # - Automatic module registration
    # - Authorization inheritance with 5-level priority system
    # - Shared query methods (authorization_for_setting, settings_requiring, authorized_settings)
    # - Conflict detection with other authorization modules
    #
    # ## Design Principle
    #
    # PolicyBasedAuthorization provides the ENTIRE shared interface, eliminating code
    # duplication between Pundit and ActionPolicy. Policy modules only need to:
    # 1. Include PolicyBasedAuthorization
    # 2. Call register_policy_module
    # 3. Implement policy_module_name
    #
    # ## Integration with Sprint 11
    #
    # This module uses Sprint 11's ModuleRegistry and inheritable options system:
    # - Automatic module registration via `register_policy_module`
    # - `on_setting_defined` hooks to capture authorization metadata
    # - Inheritable options with :replace merge strategy
    #
    # @example Creating a policy-based module
    #   module Pundit
    #     extend ActiveSupport::Concern
    #     include PolicyBasedAuthorization
    #
    #     # Register as policy module (handles all registration)
    #     register_policy_module(:pundit, self)
    #
    #     module ClassMethods
    #       def policy_module_name
    #         :pundit
    #       end
    #     end
    #   end
    #
    module PolicyBasedAuthorization
      extend ActiveSupport::Concern

      # Track registered policy modules
      @registered_modules = {}

      class << self
        attr_reader :registered_modules
      end

      # Hook to capture authorization metadata when settings are defined
      # This hook runs for ALL policy modules (Pundit, ActionPolicy)
      ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
        # Check if any policy-based module is included
        policy_module = model_class.ancestors.find { |ancestor|
          PolicyBasedAuthorization.registered_modules.key?(ancestor)
        }

        next unless policy_module  # Skip if no policy module included

        module_name = PolicyBasedAuthorization.registered_modules[policy_module]

        if setting.options.key?(:authorize_with)
          ModelSettings::ModuleRegistry.set_module_metadata(
            model_class,
            module_name,
            setting.name,
            setting.options[:authorize_with]
          )
        end
      end

      # Register a policy-based authorization module
      #
      # This class method handles all module registration, eliminating duplication
      # between policy modules. Registers:
      # - Module with ModuleRegistry
      # - Exclusive authorization group
      # - Query methods (authorization_for_setting, settings_requiring, authorized_settings)
      # - authorize_with option validation
      # - authorize_with as inheritable option
      # - on_setting_defined hook to capture metadata
      #
      # @param module_name [Symbol] Module name (:pundit, :action_policy)
      # @param module_const [Module] Module constant (self)
      #
      # @example
      #   PolicyBasedAuthorization.register_policy_module(:pundit, self)
      #
      def self.register_policy_module(module_name, module_const)
        # Store the module name for later use in included block
        @registered_modules[module_const] = module_name
        # Register module
        ModelSettings::ModuleRegistry.register_module(module_name, module_const)

        # Register as part of exclusive authorization group
        ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, module_name)

        # Register query methods for introspection
        ModelSettings::ModuleRegistry.register_query_method(
          module_name, :authorization_for_setting, :class,
          description: "Get the authorization method for a specific setting",
          parameters: {name: :Symbol},
          returns: "Symbol, nil"
        )
        ModelSettings::ModuleRegistry.register_query_method(
          module_name, :settings_requiring, :class,
          description: "Get all settings that require a specific permission",
          parameters: {permission: :Symbol},
          returns: "Array<Symbol>"
        )
        ModelSettings::ModuleRegistry.register_query_method(
          module_name, :authorized_settings, :class,
          description: "Get all settings that have authorization",
          returns: "Array<Symbol>"
        )

        # Register authorize_with option validation
        ModelSettings::ModuleRegistry.register_option(:authorize_with) do |value, setting, model_class|
          unless value.is_a?(Symbol)
            policy_type = (module_name == :action_policy) ? "rule" : "method"
            raise ArgumentError,
              "authorize_with must be a Symbol pointing to a policy #{policy_type} " \
              "(got #{value.class}). " \
              "Example: authorize_with: :manage_billing?\n" \
              "Use Roles Module for simple role-based checks with arrays."
          end
        end

        # Register authorize_with as inheritable option with :replace strategy
        # Child settings override parent policy (no inheritance of policy references)
        ModelSettings::ModuleRegistry.register_inheritable_option(
          :authorize_with,
          merge_strategy: :replace
        )
      end

      # No included block needed here - conflict detection is handled by
      # individual policy modules (Pundit, ActionPolicy) in their own included blocks

      module ClassMethods
        # Abstract method - must be implemented by including module
        #
        # @return [Symbol] Module name (:pundit, :action_policy)
        # @raise [NotImplementedError] If not implemented by including module
        #
        def policy_module_name
          raise NotImplementedError,
            "Policy-based modules must implement policy_module_name class method"
        end

        # Get the authorization method for a specific setting with inheritance
        #
        # Uses 5-level priority system to resolve authorization:
        # 1. Explicit setting value
        # 2. Explicit :inherit keyword
        # 3. Setting inherit_authorization option
        # 4. Model-level configuration
        # 5. Global configuration
        #
        # @param name [Symbol] Setting name
        # @return [Symbol, nil] Policy method/rule name, or nil if not authorized
        #
        # @example
        #   User.authorization_for_setting(:billing_override)
        #   # => :manage_billing?
        #
        # @example With inheritance
        #   User.authorization_for_setting(:nested_child)
        #   # => :manage_parent? (inherited from parent)
        #
        def authorization_for_setting(name)
          setting = find_setting_by_name(name)
          return nil unless setting

          resolve_authorization_with_priority(setting, :authorize_with)
        end

        # Get all settings that require a specific permission
        #
        # @param permission [Symbol] Policy method/rule name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_requiring(:admin?)
        #   # => [:api_access, :system_config]
        #
        def settings_requiring(permission)
          all_settings_recursive.select do |setting|
            resolve_authorization_with_priority(setting, :authorize_with) == permission
          end.map(&:name)
        end

        # Get all settings that have authorization (including inherited)
        #
        # @return [Array<Symbol>] Array of setting names
        #
        def authorized_settings
          all_settings_recursive.select do |setting|
            resolve_authorization_with_priority(setting, :authorize_with).present?
          end.map(&:name)
        end

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
        # @param aspect [Symbol] Authorization aspect (:authorize_with)
        # @param visited [Set] Set of visited settings (for cycle detection)
        # @return [Symbol, nil] Resolved authorization method/rule, or nil
        #
        def resolve_authorization_with_priority(setting, aspect, visited = Set.new)
          # Level 1: Explicit setting value (not nil, not :inherit)
          explicit = setting.options[aspect]
          return explicit if explicit.present? && explicit != :inherit

          # Level 2: Explicit :inherit keyword
          if explicit == :inherit
            return resolve_from_parent(setting, aspect, visited)
          end

          # Level 3: Setting inherit_authorization option
          if setting.options.key?(:inherit_authorization)
            inherit_option = setting.options[:inherit_authorization]
            case inherit_option
            when true, :view_only, :edit_only
              # Policy-based uses single authorize_with, so view_only/edit_only = inherit
              return resolve_from_parent(setting, aspect, visited)
            when false
              # Explicitly disabled - return nil immediately (don't check lower levels)
              return nil
            end
          end

          # Level 4: Model-level configuration
          model_config = settings_config_value(:inherit_authorization) if respond_to?(:settings_config_value, true)
          if model_config
            case model_config
            when true, :view_only, :edit_only
              # Policy-based uses single authorize_with, so view_only/edit_only = inherit
              return resolve_from_parent(setting, aspect, visited)
            when false
              # Explicitly disabled at model level
              return nil
            end
          end

          # Level 5: Global configuration
          if ModelSettings.configuration.respond_to?(:inherit_authorization)
            global_config = ModelSettings.configuration.inherit_authorization
            if global_config == true
              return resolve_from_parent(setting, aspect, visited)
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
        # @param aspect [Symbol] Authorization aspect (:authorize_with)
        # @param visited [Set] Set of visited settings (for cycle detection)
        # @return [Symbol, nil] Resolved authorization, or nil if no parent
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
          return nil unless parent  # No parent = no authorization

          # Recursively resolve parent's authorization
          resolve_authorization_with_priority(parent, aspect, visited)
        end

        # Find setting by name (utility method)
        #
        # Searches recursively through all settings (including nested).
        #
        # @param name [Symbol] Setting name
        # @return [ModelSettings::Setting, nil] Setting object or nil if not found
        #
        def find_setting_by_name(name)
          all_settings_recursive.find { |s| s.name == name }
        end
      end

      # Resolve authorization for a setting (instance method utility)
      #
      # This is a utility method for modules to use. Each module should define
      # its OWN instance-level DSL methods.
      #
      # @param setting_name [Symbol] Setting name
      # @param aspect [Symbol] Authorization aspect (:authorize_with, :viewable_by, etc.)
      # @return [Symbol, Array, nil] Resolved authorization
      #
      # @example In Pundit module
      #   def authorized?(setting_name, user:)
      #     authorization = resolve_authorization_for(setting_name, :authorize_with)
      #     # ... Pundit-specific logic ...
      #   end
      #
      def resolve_authorization_for(setting_name, aspect = :authorize_with)
        setting = self.class.find_setting_by_name(setting_name)
        return nil unless setting

        self.class.resolve_authorization_with_priority(setting, aspect)
      end
    end
  end
end
