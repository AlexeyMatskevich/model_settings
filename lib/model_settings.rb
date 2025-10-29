# frozen_string_literal: true

require_relative "model_settings/version"
require_relative "model_settings/setting"
require_relative "model_settings/configuration"
require_relative "model_settings/module_registry"
require_relative "model_settings/callbacks"
require_relative "model_settings/validation"
require_relative "model_settings/deprecation"
require_relative "model_settings/query"
require_relative "model_settings/dsl"
require_relative "model_settings/adapters/base"
require_relative "model_settings/adapters/column"
require_relative "model_settings/adapters/json"
require_relative "model_settings/adapters/store_model"

# Optional modules
require_relative "model_settings/modules/i18n" if defined?(I18n)

module ModelSettings
  class Error < StandardError; end
  class CyclicSyncError < Error; end

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
