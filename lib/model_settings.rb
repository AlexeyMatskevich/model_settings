# frozen_string_literal: true

require_relative "model_settings/version"
require_relative "model_settings/setting"
require_relative "model_settings/configuration"
require_relative "model_settings/error_messages"
require_relative "model_settings/module_registry"
require_relative "model_settings/callbacks"
require_relative "model_settings/validation"
require_relative "model_settings/deprecation"
require_relative "model_settings/deprecation_auditor"
require_relative "model_settings/deprecated_settings_lister"
require_relative "model_settings/query"
require_relative "model_settings/dependency_engine"
require_relative "model_settings/documentation"
require_relative "model_settings/dsl"
require_relative "model_settings/validators/boolean_value_validator"
require_relative "model_settings/validators/array_type_validator"
require_relative "model_settings/adapters/base"
require_relative "model_settings/adapters/column"
require_relative "model_settings/adapters/json"
require_relative "model_settings/adapters/store_model"

# Optional modules
require_relative "model_settings/modules/i18n" if defined?(I18n)

# Authorization utilities (used by policy-based modules)
require_relative "model_settings/modules/policy_based_authorization"

# Authorization modules (mutually exclusive)
require_relative "model_settings/modules/roles"
require_relative "model_settings/modules/pundit"
require_relative "model_settings/modules/action_policy"

module ModelSettings
  class Error < StandardError; end
  class CyclicSyncError < Error; end

  # Register merge strategies for core options (opt-in inheritance)
  # These options are NOT auto-included in inheritable_options by default.
  # Users must explicitly add them to config.inheritable_options if they want inheritance.
  ModuleRegistry.register_inheritable_option(:metadata, merge_strategy: :merge, auto_include: false)
  ModuleRegistry.register_inheritable_option(:cascade, merge_strategy: :merge, auto_include: false)

  # Register authorization modules
  ModuleRegistry.register_module(:roles, Modules::Roles)
  ModuleRegistry.register_module(:pundit, Modules::Pundit)
  ModuleRegistry.register_module(:action_policy, Modules::ActionPolicy)

  # Register authorization modules as mutually exclusive
  ModuleRegistry.register_exclusive_group(:authorization, :roles)
  ModuleRegistry.register_exclusive_group(:authorization, :pundit)
  ModuleRegistry.register_exclusive_group(:authorization, :action_policy)

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
