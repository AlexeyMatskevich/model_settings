# frozen_string_literal: true

require "active_support/concern"

module ModelSettings
  # Callbacks module for settings lifecycle hooks
  #
  # Provides callback execution for setting state changes:
  # - before_enable / after_enable
  # - before_disable / after_disable
  # - before_toggle / after_toggle
  # - after_change_commit (for async operations)
  #
  # Usage:
  #   setting :premium_mode,
  #           before_enable: :check_subscription,
  #           after_enable: :notify_activation,
  #           after_disable: :cleanup_premium_features
  #
  #   setting :notifications,
  #           after_change_commit: :sync_to_external_service
  module Callbacks
    extend ActiveSupport::Concern

    included do
      # Track callbacks that need to be run after commit (only for ActiveRecord models)
      if respond_to?(:after_commit)
        after_commit :run_pending_setting_callbacks, if: :has_pending_setting_callbacks?
      end
    end

    # Execute callbacks for a setting change
    #
    # @param setting [Setting] The setting object
    # @param action [Symbol] The action (:enable, :disable, :toggle, :change, :validation, :destroy, :change_rollback)
    # @param timing [Symbol] When to run (:before, :after)
    # @param phase [Symbol, nil] Lifecycle phase (:create, :update, :destroy) for :on option
    # @return [Boolean] true if all callbacks succeeded
    def execute_setting_callbacks(setting, action, timing, phase: nil)
      callback_name = :"#{timing}_#{action}"
      callback = setting.options[callback_name]

      return true unless callback

      # Check callback conditions (:if, :unless, :on)
      return true unless should_execute_callback?(setting, phase)

      case callback
      when Symbol
        public_send(callback)
      when Proc
        instance_exec(&callback)
      when Array
        callback.each do |cb|
          case cb
          when Symbol
            public_send(cb)
          when Proc
            instance_exec(&cb)
          end
        end
      end

      true
    rescue => e
      # Log error but don't raise to allow operation to continue
      Rails.logger.error("Setting callback #{callback_name} failed: #{e.message}") if defined?(Rails)
      false
    end

    # Execute around callback that wraps an operation
    #
    # Around callbacks must yield to execute the wrapped operation.
    # If the callback doesn't yield, the operation is aborted.
    #
    # @param setting [Setting] The setting object
    # @param action [Symbol] The action (:enable, :disable, :change)
    # @yield The block containing the actual operation
    # @return [Boolean] true if callback executed (even if it didn't yield)
    #
    # @example
    #   execute_around_callback(setting, :enable) do
    #     # This code runs only if the around callback yields
    #     self.feature = true
    #   end
    #
    def execute_around_callback(setting, action, &operation)
      callback_name = :"around_#{action}"
      callback = setting.options[callback_name]

      # No around callback - just execute the operation
      unless callback
        operation.call
        return true
      end

      # Execute around callback with the operation block
      case callback
      when Symbol
        # Method must accept a block and yield to it
        public_send(callback, &operation)
      when Proc
        # Execute the proc in instance context with yield pointing to operation
        # Wrap in a new Proc so yield is available to the callback
        proc { instance_exec(&callback) }.call(&operation)
      when Array
        # Only execute first around callback (around callbacks don't chain)
        cb = callback.first
        case cb
        when Symbol
          public_send(cb, &operation)
        when Proc
          proc { instance_exec(&cb) }.call(&operation)
        end
      end

      true
    rescue => e
      # Log error but don't raise to allow operation to continue
      Rails.logger.error("Setting callback #{callback_name} failed: #{e.message}") if defined?(Rails)
      false
    end

    # Track that a setting has changed and needs after_commit callbacks
    #
    # @param setting [Setting] The setting that changed
    def track_setting_change_for_commit(setting)
      @_pending_setting_callbacks ||= []
      @_pending_setting_callbacks << setting unless @_pending_setting_callbacks.include?(setting)
    end

    # Check if there are pending callbacks to run
    #
    # @return [Boolean]
    def has_pending_setting_callbacks?
      @_pending_setting_callbacks&.any? || false
    end

    # Run all pending after_commit callbacks
    def run_pending_setting_callbacks
      return unless @_pending_setting_callbacks

      callbacks_to_run = @_pending_setting_callbacks.dup
      @_pending_setting_callbacks = []

      callbacks_to_run.each do |setting|
        callback = setting.options[:after_change_commit]
        next unless callback

        case callback
        when Symbol
          public_send(callback)
        when Proc
          instance_exec(&callback)
        when Array
          callback.each do |cb|
            case cb
            when Symbol
              public_send(cb)
            when Proc
              instance_exec(&cb)
            end
          end
        end
      rescue => e
        Rails.logger.error("Setting after_change_commit callback failed: #{e.message}") if defined?(Rails)
      end
    end

    private

    # Check if callback should be executed based on conditions
    #
    # @param setting [Setting] The setting object
    # @param phase [Symbol, nil] Current lifecycle phase
    # @return [Boolean] true if callback should execute
    def should_execute_callback?(setting, phase)
      # Check :if condition
      if setting.options[:if]
        condition_method = setting.options[:if]
        return false unless public_send(condition_method)
      end

      # Check :unless condition
      if setting.options[:unless]
        condition_method = setting.options[:unless]
        return false if public_send(condition_method)
      end

      # Check :on lifecycle phase
      if setting.options[:on] && phase
        required_phase = setting.options[:on]
        return false unless phase == required_phase
      end

      true
    end

    module ClassMethods
      # Find setting by name for callback execution
      #
      # @param name [Symbol] Setting name
      # @return [Setting, nil]
      def find_setting_for_callbacks(name)
        find_setting(name)
      end
    end
  end
end
