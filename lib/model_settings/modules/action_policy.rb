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

      # Register as policy-based authorization module FIRST (before include)
      # This single call handles all registration (module, exclusive group, query methods, etc.)
      PolicyBasedAuthorization.register_policy_module(:action_policy, self)

      # Include PolicyBasedAuthorization AFTER registration
      include PolicyBasedAuthorization

      included do
        # Add to active modules FIRST (before conflict check)
        settings_add_module(:action_policy) if respond_to?(:settings_add_module)

        # Check for conflicts with other authorization modules
        ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :action_policy)
      end

      module ClassMethods
        # Return the module name for PolicyBasedAuthorization
        #
        # @return [Symbol] The module name
        #
        def policy_module_name
          :action_policy
        end
      end
    end
  end
end
