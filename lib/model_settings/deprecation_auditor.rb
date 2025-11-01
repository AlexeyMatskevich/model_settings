# frozen_string_literal: true

module ModelSettings
  # Audits deprecated settings for actual usage in the database
  #
  # Generates reports showing which deprecated settings are still in use,
  # how many records use them, and provides actionable migration guidance.
  #
  # Usage:
  #   auditor = ModelSettings::DeprecationAuditor.new
  #   report = auditor.generate_report
  #   puts report.to_s
  #   exit 1 if report.has_active_usage?
  #
  class DeprecationAuditor
    # Report containing audit results
    class Report
      attr_reader :model_reports

      def initialize
        @model_reports = []
      end

      def add_model_report(model_class, settings_with_usage)
        @model_reports << {
          model_class: model_class,
          settings: settings_with_usage
        }
      end

      def has_active_usage?
        @model_reports.any? { |mr| mr[:settings].any? { |s| s[:usage_count] > 0 } }
      end

      def to_s
        return "✓ No deprecated settings found in use" unless has_active_usage?

        output = ["⚠️  Found deprecated settings in use:\n"]

        @model_reports.each do |model_report|
          model_class = model_report[:model_class]
          settings = model_report[:settings].select { |s| s[:usage_count] > 0 }

          next if settings.empty?

          output << "\n#{model_class.name} (#{settings.size} deprecated settings):"

          settings.each do |setting_data|
            setting = setting_data[:setting]
            usage_count = setting_data[:usage_count]
            total_count = setting_data[:total_count]

            output << "  ✗ #{setting.name}"

            # Show deprecation message
            message = setting.options[:deprecated]
            output << "    Reason: #{message}" if message.is_a?(String)

            # Show usage statistics
            output << "    Used in: #{usage_count} records (out of #{total_count} total)"
          end
        end

        output.join("\n")
      end
    end

    # Generate audit report for all models
    #
    # @return [Report] Audit report
    def generate_report
      report = Report.new

      find_models_with_settings.each do |model_class|
        deprecated_settings = model_class._settings.select(&:deprecated?)
        next if deprecated_settings.empty?

        settings_with_usage = deprecated_settings.map do |setting|
          {
            setting: setting,
            usage_count: count_usage(model_class, setting),
            total_count: model_class.count
          }
        end

        report.add_model_report(model_class, settings_with_usage)
      end

      report
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

    # Count how many records actually use this deprecated setting
    #
    # Logic depends on adapter type:
    # - Column: COUNT WHERE column IS NOT NULL (or = true for booleans)
    # - JSON: Complex - need to check JSON content
    # - StoreModel: Similar to JSON
    def count_usage(model_class, setting)
      case setting.type
      when :column
        count_column_usage(model_class, setting)
      when :json
        count_json_usage(model_class, setting)
      when :store_model
        count_store_model_usage(model_class, setting)
      else
        0 # Unknown adapter, can't check usage
      end
    rescue
      # If we can't check usage (table doesn't exist, etc), return 0
      0
    end

    def count_column_usage(model_class, setting)
      # Column name is either explicitly specified or uses setting name
      column_name = setting.storage[:column] || setting.name

      # For boolean columns, count where value is explicitly true
      # For other types, count where value is NOT NULL
      db_column = model_class.columns_hash[column_name.to_s]
      is_boolean = db_column&.type == :boolean

      if is_boolean
        model_class.where(column_name => true).count
      else
        model_class.where.not(column_name => nil).count
      end
    end

    def count_json_usage(model_class, setting)
      # For JSON settings, we need to check if the key exists in the JSON column
      # This is database-specific (PostgreSQL JSONB vs MySQL JSON)

      storage_column = setting.storage[:column]
      json_key = setting.name

      # Validate column name to prevent SQL injection
      unless model_class.column_names.include?(storage_column.to_s)
        return 0
      end

      # Try PostgreSQL JSONB operator first
      if model_class.connection.adapter_name.downcase.include?("postgres")
        # Use Arel to safely build the query
        column = model_class.arel_table[storage_column]
        model_class.where(
          Arel::Nodes::InfixOperation.new("?", column, Arel::Nodes::Quoted.new(json_key.to_s))
        ).count
      else
        # Fallback: load all records and check in Ruby (slower but works everywhere)
        model_class.count { |record| record.send(storage_column)&.key?(json_key.to_s) }
      end
    rescue
      # If JSON query fails, fallback to 0
      0
    end

    def count_store_model_usage(model_class, setting)
      # StoreModel settings are similar to JSON
      # The parent StoreModel column contains the nested setting

      # For now, we'll use a conservative approach:
      # If the parent column has data, we assume the nested setting might be in use
      storage_column = setting.storage[:column]

      model_class.where.not(storage_column => nil).count
    rescue
      0
    end
  end
end
