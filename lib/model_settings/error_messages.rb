# frozen_string_literal: true

module ModelSettings
  # Provides improved error messages with context and helpful suggestions
  module ErrorMessages
    class << self
      # Error for missing adapter configuration
      def adapter_configuration_error(adapter_type, setting, model_class)
        case adapter_type
        when :json
          json_adapter_error(setting, model_class)
        when :store_model
          store_model_adapter_error(setting, model_class)
        else
          generic_adapter_error(adapter_type, setting, model_class)
        end
      end

      # Error for unknown storage type
      def unknown_storage_type_error(type, setting, model_class)
        available_types = [:column, :json, :store_model]

        suggestion = did_you_mean(type.to_s, available_types.map(&:to_s))

        message = <<~ERROR
          Unknown storage type: #{type.inspect} for setting #{setting.name.inspect}

          Location: #{model_class.name}

          Available storage types:
            - :column      (stores in database column)
            - :json        (stores in JSONB column)
            - :store_model (stores using StoreModel gem)
        ERROR

        if suggestion
          message += "\nDid you mean: #{suggestion.inspect}?"
        end

        message += <<~EXAMPLE

          Example usage:
            setting :#{setting.name}, type: :column, default: false

            # Or with JSON:
            setting :#{setting.name}, type: :json, storage: {column: :settings_json}
        EXAMPLE

        message.strip
      end

      # Error for module conflicts
      def module_conflict_error(group_name, active_modules)
        modules_list = active_modules.map { |m| ":#{m}" }.join(", ")

        <<~ERROR
          Cannot use multiple modules from the '#{group_name}' exclusive group.

          Active modules: #{modules_list}

          These modules are mutually exclusive because they provide conflicting
          functionality. You must choose only ONE module from this group.

          To fix this issue:
            1. Decide which module best fits your needs
            2. Remove the include statement for other modules

          Example for authorization modules:
            # Choose ONE of these:
            include ModelSettings::Modules::Roles        # Simple RBAC
            include ModelSettings::Modules::Pundit       # Pundit integration
            include ModelSettings::Modules::ActionPolicy # ActionPolicy integration
        ERROR
      end

      # Error for cyclic sync dependencies
      def cyclic_sync_error(cycle)
        cycle_path = cycle.map { |s| ":#{s}" }.join(" → ")

        <<~ERROR
          Cycle detected in sync dependencies: #{cycle_path}

          Sync relationships cannot form cycles. Each setting can only sync in one direction.

          To fix this issue:
            1. Remove one of the sync relationships to break the cycle
            2. Choose a clear direction for data flow

          Example fix:
            # Before (creates cycle):
            setting :a, sync: {target: :b, mode: :forward}
            setting :b, sync: {target: :a, mode: :forward}  # ❌ Creates cycle

            # After (no cycle):
            setting :a, sync: {target: :b, mode: :forward}  # ✓ Clear direction
            setting :b  # Remove sync
        ERROR
      end

      # Error for infinite cascade
      def infinite_cascade_error(iterations, max_iterations)
        <<~ERROR
          Infinite cascade detected after #{iterations} iterations (max: #{max_iterations})

          This usually means you have circular cascade relationships between settings.

          Common causes:
            1. Setting A cascades to B, and B cascades back to A
            2. Long cascade chain that modifies the parent setting
            3. Callback that re-enables a disabled setting

          To debug this issue:
            1. Check your cascade configurations for circular dependencies
            2. Examine callbacks that modify settings
            3. Use User.settings_debug to visualize dependencies

          Example problematic configuration:
            setting :parent, cascade: {enable: true} do
              setting :child, cascade: {enable: true} do
                # If child somehow enables parent, infinite loop!
              end
            end
        ERROR
      end

      # Error for unsupported documentation format
      def unsupported_format_error(format, available_formats)
        formats_list = available_formats.map { |f| ":#{f}" }.join(", ")
        suggestion = did_you_mean(format.to_s, available_formats.map(&:to_s))

        message = <<~ERROR
          Unsupported documentation format: #{format.inspect}

          Available formats: #{formats_list}
        ERROR

        if suggestion
          message += "\nDid you mean: #{suggestion.inspect}?"
        end

        message += <<~EXAMPLE

          Example usage:
            User.generate_settings_documentation(format: :markdown)
        EXAMPLE

        message.strip
      end

      private

      def json_adapter_error(setting, model_class)
        <<~ERROR
          JSON adapter requires a storage column to be specified.

          Setting: #{setting.name.inspect}
          Model: #{model_class.name}

          You must specify which JSONB column to store the setting in.

          Fix by adding storage configuration:
            setting :#{setting.name},
              type: :json,
              storage: {column: :settings_json}  # ← Add this

          Make sure the column exists in your database:
            add_column :#{model_class.table_name}, :settings_json, :jsonb
        ERROR
      end

      def store_model_adapter_error(setting, model_class)
        <<~ERROR
          StoreModel adapter requires a storage column to be specified.

          Setting: #{setting.name.inspect}
          Model: #{model_class.name}

          You must specify which column contains the StoreModel instance.

          Fix by adding storage configuration:
            setting :#{setting.name},
              type: :store_model,
              storage: {column: :preferences}  # ← Add this

          Make sure you have a StoreModel defined:
            class Preferences
              include StoreModel::Model
              attribute :#{setting.name}, :boolean, default: false
            end

          And the column exists:
            add_column :#{model_class.table_name}, :preferences, :jsonb
        ERROR
      end

      def generic_adapter_error(adapter_type, setting, model_class)
        <<~ERROR
          #{adapter_type.to_s.capitalize} adapter configuration error.

          Setting: #{setting.name.inspect}
          Model: #{model_class.name}

          Please check the adapter documentation for proper configuration.
        ERROR
      end

      # Simple "did you mean" implementation
      def did_you_mean(input, candidates)
        return nil if input.nil? || candidates.empty?

        # Find candidates with Levenshtein distance <= 2
        matches = candidates.select do |candidate|
          distance = levenshtein_distance(input.to_s, candidate.to_s)
          distance <= 2 && distance > 0
        end

        matches.min_by { |candidate| levenshtein_distance(input.to_s, candidate.to_s) }
      end

      # Calculate Levenshtein distance between two strings
      def levenshtein_distance(str1, str2)
        matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

        (0..str1.length).each { |i| matrix[i][0] = i }
        (0..str2.length).each { |j| matrix[0][j] = j }

        (1..str1.length).each do |i|
          (1..str2.length).each do |j|
            cost = (str1[i - 1] == str2[j - 1]) ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,      # deletion
              matrix[i][j - 1] + 1,      # insertion
              matrix[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        matrix[str1.length][str2.length]
      end
    end
  end
end
