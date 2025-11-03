# frozen_string_literal: true

# Helper module for saving and restoring ModuleRegistry state in tests
module RegistryStateHelper
  # Save the current state of ModuleRegistry
  # Returns a hash that can be passed to restore_registry_state
  def save_registry_state
    {
      modules: ModelSettings::ModuleRegistry.instance_variable_get(:@modules).dup,
      exclusive_groups: ModelSettings::ModuleRegistry.instance_variable_get(:@exclusive_groups).dup,
      registered_options: ModelSettings::ModuleRegistry.instance_variable_get(:@registered_options).dup,
      definition_hooks: ModelSettings::ModuleRegistry.instance_variable_get(:@definition_hooks).dup,
      compilation_hooks: ModelSettings::ModuleRegistry.instance_variable_get(:@compilation_hooks).dup,
      before_change_hooks: ModelSettings::ModuleRegistry.instance_variable_get(:@before_change_hooks).dup,
      after_change_hooks: ModelSettings::ModuleRegistry.instance_variable_get(:@after_change_hooks).dup,
      module_callback_configs: ModelSettings::ModuleRegistry.instance_variable_get(:@module_callback_configs).dup,
      query_methods: ModelSettings::ModuleRegistry.instance_variable_get(:@query_methods).dup,
      registered_inheritable_options: ModelSettings::ModuleRegistry.instance_variable_get(:@registered_inheritable_options).dup
    }
  end

  # Restore ModuleRegistry state from a saved state hash
  # @param state [Hash] State hash returned by save_registry_state
  def restore_registry_state(state)
    ModelSettings::ModuleRegistry.instance_variable_set(:@modules, state[:modules])
    ModelSettings::ModuleRegistry.instance_variable_set(:@exclusive_groups, state[:exclusive_groups])
    ModelSettings::ModuleRegistry.instance_variable_set(:@registered_options, state[:registered_options])
    ModelSettings::ModuleRegistry.instance_variable_set(:@definition_hooks, state[:definition_hooks])
    ModelSettings::ModuleRegistry.instance_variable_set(:@compilation_hooks, state[:compilation_hooks])
    ModelSettings::ModuleRegistry.instance_variable_set(:@before_change_hooks, state[:before_change_hooks])
    ModelSettings::ModuleRegistry.instance_variable_set(:@after_change_hooks, state[:after_change_hooks])
    ModelSettings::ModuleRegistry.instance_variable_set(:@module_callback_configs, state[:module_callback_configs])
    ModelSettings::ModuleRegistry.instance_variable_set(:@query_methods, state[:query_methods])
    ModelSettings::ModuleRegistry.instance_variable_set(:@registered_inheritable_options, state[:registered_inheritable_options])
  end
end

RSpec.configure do |config|
  config.include RegistryStateHelper
end
