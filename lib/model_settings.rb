# frozen_string_literal: true

require_relative "model_settings/version"
require_relative "model_settings/setting"
require_relative "model_settings/configuration"
require_relative "model_settings/dsl"
require_relative "model_settings/adapters/base"
require_relative "model_settings/adapters/column"

module ModelSettings
  class Error < StandardError; end

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
