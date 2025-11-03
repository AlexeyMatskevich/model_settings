# frozen_string_literal: true

module ModelSettings
  module Modules
    # ActionPolicy authorization module for settings
    #
    # This module integrates with ActionPolicy for authorization of settings,
    # allowing you to use your existing ActionPolicy rules to control access.
    #
    # IMPORTANT: This module is mutually exclusive with Roles and Pundit modules.
    # You can only use ONE authorization module at a time.
    #
    # @example Basic usage
    #   class User < ApplicationRecord
    #     include ModelSettings::DSL
    #     include ModelSettings::Modules::ActionPolicy
    #
    #     setting :billing_override,
    #             type: :column,
    #             authorize_with: :manage_billing?
    #
    #     setting :api_access,
    #             type: :column,
    #             authorize_with: :admin?
    #   end
    #
    # @example In your UserPolicy
    #   class UserPolicy < ApplicationPolicy
    #     def manage_billing?
    #       user.admin? || user.finance?
    #     end
    #
    #     def admin?
    #       user.admin?
    #     end
    #
    #     def permitted_settings
    #       record.class._authorized_settings.select do |name, method|
    #         public_send(method)
    #       end.keys
    #     end
    #   end
    #
    # @example In your controller
    #   class UsersController < ApplicationController
    #     def update
    #       @user = User.find(params[:id])
    #       authorize! @user
    #
    #       # Get settings allowed by policy
    #       policy = authorized(@user)
    #       allowed_settings = policy.permitted_settings
    #
    #       # Filter params
    #       permitted_params = params.require(:user).permit(*allowed_settings)
    #       @user.update(permitted_params)
    #     end
    #   end
    #
    module ActionPolicy
      extend ActiveSupport::Concern

      # Module-level registrations (executed ONCE when module is loaded)

      # Register module
      ModelSettings::ModuleRegistry.register_module(:action_policy, self)

      # Register as part of exclusive authorization group
      ModelSettings::ModuleRegistry.register_exclusive_group(:authorization, :action_policy)

      # Register query methods for introspection
      ModelSettings::ModuleRegistry.register_query_method(
        :action_policy, :authorization_for_setting, :class,
        description: "Get the authorization method for a specific setting",
        parameters: {name: :Symbol},
        returns: "Symbol, nil"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :action_policy, :settings_requiring, :class,
        description: "Get all settings that require a specific permission",
        parameters: {permission: :Symbol},
        returns: "Array<Symbol>"
      )
      ModelSettings::ModuleRegistry.register_query_method(
        :action_policy, :authorized_settings, :class,
        description: "Get all settings that have authorization",
        returns: "Array<Symbol>"
      )

      # Register authorize_with option
      ModelSettings::ModuleRegistry.register_option(:authorize_with) do |setting, value|
        unless value.is_a?(Symbol)
          raise ArgumentError,
            "authorize_with must be a Symbol pointing to a policy rule " \
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

      # Hook to capture authorization metadata when settings are defined
      ModelSettings::ModuleRegistry.on_setting_defined do |setting, model_class|
        next unless ModelSettings::ModuleRegistry.module_included?(:action_policy, model_class)

        if setting.options.key?(:authorize_with)
          ModelSettings::ModuleRegistry.set_module_metadata(
            model_class,
            :action_policy,
            setting.name,
            setting.options[:authorize_with]
          )
        end
      end

      included do
        # Add to active modules FIRST (before conflict check)
        settings_add_module(:action_policy) if respond_to?(:settings_add_module)

        # Check for conflicts with other authorization modules
        settings_check_exclusive_conflict!(:action_policy) if respond_to?(:settings_check_exclusive_conflict!)
      end

      module ClassMethods
        # Get the authorization method for a specific setting
        #
        # @param name [Symbol] Setting name
        # @return [Symbol, nil] Policy rule name, or nil if not authorized
        #
        # @example
        #   User.authorization_for_setting(:billing_override)
        #   # => :manage_billing?
        #
        def authorization_for_setting(name)
          get_module_metadata(:action_policy, name)
        end

        # Get all settings that require a specific permission
        #
        # @param permission [Symbol] Policy rule name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_requiring(:admin?)
        #   # => [:api_access, :system_config]
        #
        def settings_requiring(permission)
          all_auth = get_module_metadata(:action_policy)

          all_auth.select { |_name, method| method == permission }.keys
        end

        # Get all settings that have authorization
        #
        # @return [Array<Symbol>] Array of setting names
        #
        def authorized_settings
          get_module_metadata(:action_policy).keys
        end
      end
    end
  end
end
