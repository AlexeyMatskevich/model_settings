# frozen_string_literal: true

module ModelSettings
  # DependencyEngine handles cascade, sync, and dependency management for settings.
  #
  # Key responsibilities:
  # 1. Build DAG (Directed Acyclic Graph) of setting dependencies
  # 2. Detect cycles in sync relationships at definition time
  # 3. Pre-compute topological sort for sync execution order
  # 4. Apply cascades (enable/disable propagation)
  # 5. Execute syncs in correct order
  #
  # Performance optimizations:
  # - Heavy computation at definition time (Rails boot)
  # - Pre-computed execution order (no graph traversal at runtime)
  # - Wave-based execution with early termination
  # - Set operations for deduplication
  #
  # Example:
  #   class User < ApplicationRecord
  #     include ModelSettings::DSL
  #
  #     setting :billing_enabled, cascade: { disable: true } do
  #       setting :invoices
  #       setting :receipts
  #     end
  #
  #     setting :feature_a, sync: { target: :feature_b, mode: :inverse }
  #   end
  class DependencyEngine
    MAX_ITERATIONS = 100

    attr_reader :model_class, :settings, :sync_execution_order

    def initialize(model_class)
      @model_class = model_class
      @settings = model_class._settings
      @sync_execution_order = []
    end

    # Validate sync graph for cycles and build execution order
    # Called at definition time (Rails boot)
    #
    # @raise [CyclicSyncError] if cycles detected
    # @return [void]
    def compile!
      validate_sync_graph!
      extract_storage_columns
    end

    # Validate sync graph for cycles using DFS
    #
    # @raise [CyclicSyncError] if cycles detected
    # @return [void]
    def validate_sync_graph!
      graph = build_sync_graph
      cycles = detect_cycles(graph)

      if cycles.any?
        cycle_names = cycles.map(&:name)
        raise CyclicSyncError, ErrorMessages.cyclic_sync_error(cycle_names)
      end

      # Pre-compute execution order using topological sort
      @sync_execution_order = topological_sort(graph)
    end

    # Apply cascades and syncs for changed settings
    # Called at runtime (per model save)
    #
    # @param instance [ActiveRecord::Base] model instance
    # @param initial_changes [Array<Setting>] initially changed settings
    # @return [void]
    def execute_cascades_and_syncs(instance, initial_changes)
      current_wave = initial_changes.dup
      all_processed = Set.new
      iteration = 0

      while current_wave.any?
        # Safety check (cycles should be caught at definition time)
        raise ErrorMessages.infinite_cascade_error(iteration, MAX_ITERATIONS) if iteration >= MAX_ITERATIONS

        # Apply cascades (returns new changes)
        cascaded = apply_cascades_batch(instance, current_wave)

        # Apply syncs in pre-computed order (returns new changes)
        synced = apply_syncs_batch(instance, current_wave)

        # Mark as processed
        all_processed.merge(current_wave)

        # Next wave = new changes - already processed
        current_wave = (cascaded + synced).reject { |s| all_processed.include?(s) }
        iteration += 1
      end
    end

    private

    # Build directed graph of sync relationships
    #
    # @return [Hash<Setting, Array<Setting>>] adjacency list
    def build_sync_graph
      graph = {}

      settings.each do |setting|
        sync_config = setting.options[:sync]
        next unless sync_config

        target_name = sync_config[:target] || sync_config["target"]
        next unless target_name

        target_setting = find_setting(target_name)
        next unless target_setting

        graph[setting] ||= []
        graph[setting] << target_setting
      end

      graph
    end

    # Detect cycles in graph using DFS
    #
    # @param graph [Hash<Setting, Array<Setting>>] adjacency list
    # @return [Array<Setting>] cycle path if found, empty array otherwise
    def detect_cycles(graph)
      visited = Set.new
      rec_stack = Set.new
      cycle_path = []

      graph.each_key do |node|
        next if visited.include?(node)

        if detect_cycle_dfs(node, graph, visited, rec_stack, cycle_path)
          return cycle_path
        end
      end

      []
    end

    # DFS helper for cycle detection
    #
    # @param node [Setting] current node
    # @param graph [Hash<Setting, Array<Setting>>] adjacency list
    # @param visited [Set<Setting>] visited nodes
    # @param rec_stack [Set<Setting>] recursion stack
    # @param cycle_path [Array<Setting>] accumulator for cycle path
    # @return [Boolean] true if cycle detected
    def detect_cycle_dfs(node, graph, visited, rec_stack, cycle_path)
      visited.add(node)
      rec_stack.add(node)
      cycle_path << node

      # Check all neighbors
      neighbors = graph[node] || []
      neighbors.each do |neighbor|
        if !visited.include?(neighbor)
          return true if detect_cycle_dfs(neighbor, graph, visited, rec_stack, cycle_path)
        elsif rec_stack.include?(neighbor)
          # Found cycle
          cycle_path << neighbor
          return true
        end
      end

      # Backtrack
      rec_stack.delete(node)
      cycle_path.pop
      false
    end

    # Topological sort using Kahn's algorithm
    #
    # @param graph [Hash<Setting, Array<Setting>>] adjacency list
    # @return [Array<Setting>] settings in topological order
    def topological_sort(graph)
      # Calculate in-degrees
      in_degree = Hash.new(0)
      graph.each_value do |neighbors|
        neighbors.each { |neighbor| in_degree[neighbor] += 1 }
      end

      # Find nodes with no incoming edges
      queue = graph.keys.select { |node| in_degree[node].zero? }
      result = []

      while queue.any?
        node = queue.shift
        result << node

        # Reduce in-degree for neighbors
        neighbors = graph[node] || []
        neighbors.each do |neighbor|
          in_degree[neighbor] -= 1
          queue << neighbor if in_degree[neighbor].zero?
        end
      end

      result
    end

    # Apply cascades for a batch of changed settings
    #
    # @param instance [ActiveRecord::Base] model instance
    # @param changed_settings [Array<Setting>] changed settings
    # @return [Array<Setting>] newly changed settings from cascades
    def apply_cascades_batch(instance, changed_settings)
      newly_changed = []

      changed_settings.each do |setting|
        cascade_config = setting.options[:cascade]
        next unless cascade_config

        # Handle enable cascade
        if cascade_config[:enable] && instance.public_send("#{setting.name}_changed?")
          new_value = instance.public_send(setting.name)
          if new_value == true
            newly_changed.concat(apply_enable_cascade(instance, setting))
          end
        end

        # Handle disable cascade
        if cascade_config[:disable] && instance.public_send("#{setting.name}_changed?")
          new_value = instance.public_send(setting.name)
          if new_value == false
            newly_changed.concat(apply_disable_cascade(instance, setting))
          end
        end
      end

      newly_changed.uniq
    end

    # Apply enable cascade to children
    #
    # @param instance [ActiveRecord::Base] model instance
    # @param setting [Setting] parent setting
    # @return [Array<Setting>] changed children settings
    def apply_enable_cascade(instance, setting)
      changed = []

      setting.children.each do |child|
        current_value = instance.public_send(child.name)
        if current_value != true
          instance.public_send("#{child.name}=", true)
          changed << child
        end
      end

      changed
    end

    # Apply disable cascade to children
    #
    # @param instance [ActiveRecord::Base] model instance
    # @param setting [Setting] parent setting
    # @return [Array<Setting>] changed children settings
    def apply_disable_cascade(instance, setting)
      changed = []

      setting.children.each do |child|
        current_value = instance.public_send(child.name)
        if current_value != false
          instance.public_send("#{child.name}=", false)
          changed << child
        end
      end

      changed
    end

    # Apply syncs for a batch of changed settings
    #
    # @param instance [ActiveRecord::Base] model instance
    # @param changed_settings [Array<Setting>] changed settings
    # @return [Array<Setting>] newly changed settings from syncs
    def apply_syncs_batch(instance, changed_settings)
      newly_changed = []

      # Process in pre-computed order
      sync_execution_order.each do |setting|
        next unless changed_settings.include?(setting)

        sync_config = setting.options[:sync]
        next unless sync_config

        target_name = sync_config[:target] || sync_config["target"]
        mode = sync_config[:mode] || sync_config["mode"] || :forward

        target_setting = find_setting(target_name)
        next unless target_setting

        # Apply sync based on mode
        case mode.to_sym
        when :forward
          newly_changed.concat(apply_forward_sync(instance, setting, target_setting))
        when :inverse
          newly_changed.concat(apply_inverse_sync(instance, setting, target_setting))
        when :backward
          newly_changed.concat(apply_backward_sync(instance, setting, target_setting))
        end
      end

      newly_changed.uniq
    end

    # Apply forward sync (target = source)
    def apply_forward_sync(instance, source, target)
      source_value = instance.public_send(source.name)
      target_value = instance.public_send(target.name)

      if source_value != target_value
        instance.public_send("#{target.name}=", source_value)
        [target]
      else
        []
      end
    end

    # Apply inverse sync (target = !source)
    def apply_inverse_sync(instance, source, target)
      source_value = instance.public_send(source.name)
      target_value = instance.public_send(target.name)
      expected_target = !source_value

      if target_value != expected_target
        instance.public_send("#{target.name}=", expected_target)
        [target]
      else
        []
      end
    end

    # Apply backward sync (source = target)
    def apply_backward_sync(instance, source, target)
      target_value = instance.public_send(target.name)
      source_value = instance.public_send(source.name)

      if source_value != target_value
        instance.public_send("#{source.name}=", target_value)
        [source]
      else
        []
      end
    end

    # Find setting by name
    #
    # @param name [Symbol, String] setting name
    # @return [Setting, nil] found setting
    def find_setting(name)
      settings.find { |s| s.name.to_s == name.to_s }
    end

    # Extract storage columns for fast dirty check
    #
    # @return [void]
    def extract_storage_columns
      columns = settings.map do |setting|
        case setting.options[:type]
        when :column
          setting.name
        when :json, :store_model
          setting.storage[:column] if setting.storage.is_a?(Hash)
        end
      end.compact.uniq

      # Store as class constant for fast lookup
      model_class.const_set(:SETTINGS_COLUMNS, columns.freeze) unless model_class.const_defined?(:SETTINGS_COLUMNS)
    end
  end
end
