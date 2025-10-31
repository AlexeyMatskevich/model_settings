# frozen_string_literal: true

module ModelSettings
  module Modules
    # Pundit authorization module for settings
    #
    # This module integrates with Pundit for authorization of settings,
    # allowing you to use your existing Pundit policies to control access.
    #
    # IMPORTANT: This module is mutually exclusive with Roles and ActionPolicy modules.
    # You can only use ONE authorization module at a time.
    #
    # @example Basic usage
    #   class User < ApplicationRecord
    #     include ModelSettings::DSL
    #     include ModelSettings::Modules::Pundit
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
    #         send(method)
    #       end.keys
    #     end
    #   end
    #
    # @example In your controller
    #   class UsersController < ApplicationController
    #     def update
    #       @user = User.find(params[:id])
    #       authorize @user
    #
    #       # Get settings allowed by policy
    #       policy = policy(@user)
    #       allowed_settings = policy.permitted_settings
    #
    #       # Filter params
    #       permitted_params = params.require(:user).permit(*allowed_settings)
    #       @user.update(permitted_params)
    #     end
    #   end
    #
    module Pundit
      extend ActiveSupport::Concern

      included do
        # Check for conflicts with other authorization modules
        ModelSettings::ModuleRegistry.check_exclusive_conflict!(self, :pundit)

        # Storage for authorization metadata
        class_attribute :_authorized_settings, default: {}
      end

      module ClassMethods
        # Override setting method to capture authorize_with option
        #
        # @param name [Symbol] Setting name
        # @param options [Hash] Setting options
        # @option options [Symbol] :authorize_with Policy method name to check authorization
        #
        def setting(name, **options, &block)
          # Extract and validate authorize_with option
          if options.key?(:authorize_with)
            validate_authorize_with!(options[:authorize_with])
            _authorized_settings[name] = options.delete(:authorize_with)
          end

          super
        end

        # Get the authorization method for a specific setting
        #
        # @param name [Symbol] Setting name
        # @return [Symbol, nil] Policy method name, or nil if not authorized
        #
        # @example
        #   User.authorization_for_setting(:billing_override)
        #   # => :manage_billing?
        #
        def authorization_for_setting(name)
          _authorized_settings[name]
        end

        # Get all settings that require a specific permission
        #
        # @param permission [Symbol] Policy method name
        # @return [Array<Symbol>] Array of setting names
        #
        # @example
        #   User.settings_requiring(:admin?)
        #   # => [:api_access, :system_config]
        #
        def settings_requiring(permission)
          _authorized_settings.select { |_name, method| method == permission }.keys
        end

        # Get all settings that have authorization
        #
        # @return [Array<Symbol>] Array of setting names
        #
        def authorized_settings
          _authorized_settings.keys
        end

        private

        # Validate that authorize_with is a Symbol
        #
        # @param value [Object] Value to validate
        # @raise [ArgumentError] If value is not a Symbol
        #
        def validate_authorize_with!(value)
          unless value.is_a?(Symbol)
            raise ArgumentError,
              "authorize_with must be a Symbol pointing to a policy method " \
              "(got #{value.class}). " \
              "Example: authorize_with: :manage_billing?\n" \
              "Use Roles Module for simple role-based checks with arrays."
          end
        end
      end
    end
  end
end
