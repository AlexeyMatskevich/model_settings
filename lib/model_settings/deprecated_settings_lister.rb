# frozen_string_literal: true

module ModelSettings
  # Lists all deprecated settings across all models
  #
  # Provides a simple overview of deprecated settings without checking database usage.
  # Useful for documentation and quick audits.
  #
  # Usage:
  #   lister = ModelSettings::DeprecatedSettingsLister.new
  #   lister.print_list
  #
  class DeprecatedSettingsLister
    # Print list of all deprecated settings
    def print_list
      models = find_models_with_settings
      deprecated_count = 0

      puts "Deprecated Settings Report"
      puts "=" * 50
      puts ""

      models.each do |model_class|
        deprecated_settings = model_class._settings.select(&:deprecated?)

        next if deprecated_settings.empty?

        puts "#{model_class.name}:"
        deprecated_settings.each do |setting|
          deprecated_count += 1

          message = setting.options[:deprecated]
          message = "(no message)" if message == true

          deprecated_since = setting.options[:deprecated_since]

          puts "  - #{setting.name}"
          puts "    Message: #{message}"
          puts "    Since: #{deprecated_since}" if deprecated_since
        end
        puts ""
      end

      if deprecated_count.zero?
        puts "✓ No deprecated settings found"
      else
        puts "Found #{deprecated_count} deprecated setting(s) across #{models.size} model(s)"
      end
    end

    # Get all deprecated settings grouped by model
    #
    # @return [Hash] Hash with model class as key, deprecated settings as value
    def grouped_deprecated_settings
      result = {}

      find_models_with_settings.each do |model_class|
        deprecated_settings = model_class._settings.select(&:deprecated?)
        result[model_class] = deprecated_settings unless deprecated_settings.empty?
      end

      result
    end

    private

    # Find all models that have settings defined
    def find_models_with_settings
      return [] unless defined?(Rails)

      Rails.application.eager_load! if Rails.env.development?

      ActiveRecord::Base.descendants.select do |model|
        model.respond_to?(:_settings) && model._settings.any?
      end
    end
  end
end
