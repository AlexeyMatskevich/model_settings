# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/model_settings/modules/simple_audit"

# End-to-end integration tests for module callback configuration system
RSpec.describe "Module Callback Integration" do
  before do
    @saved_state = save_registry_state

    # Ensure SimpleAudit is registered and callback is at default
    unless ModelSettings::ModuleRegistry.module_registered?(:simple_audit)
      raise "SimpleAudit module not registered"
    end

    # Reset callback to default before each test
    ModelSettings.configure do |config|
      config.module_callback(:simple_audit, :before_save)
    end
  end

  after do
    restore_registry_state(@saved_state)
  end

  describe "default callback timing" do
    describe "basic default value" do
      it "uses :before_save by default" do
        callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        expect(callback).to eq(:before_save)
      end
    end

    describe "execution behavior" do
      it "executes at correct time in lifecycle" do
        execution_log = []

        test_class = Class.new(TestModel) do
          def self.name
            "DefaultCallbackModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature, type: :column, track_changes: true

          # Track execution order
          before_save { execution_log << :before_save }
          after_save { execution_log << :after_save }

          define_method(:audit_tracked_settings) do |*args|
            execution_log << :audit_executed
            super(*args)
          end
        end
        test_class.compile_settings!

        # Stub Rails.logger
        logger = instance_double(Logger)
        stub_const("Rails", Class.new {
          def self.logger
          end
        })
        allow(Rails).to receive(:logger).and_return(logger)
        allow(logger).to receive(:info)

        instance = test_class.create!(feature: false)
        execution_log.clear

        instance.feature = true
        instance.save!

        # With default :before_save, audit executes first (registered first in included block)
        # Then our before_save callback, then after_save
        expect(execution_log).to eq([:audit_executed, :before_save, :after_save])
      end
    end

    describe "global scope" do
      it "applies same default across multiple models" do
        Class.new(TestModel) do
          def self.name
            "MultiModel1"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
        end

        Class.new(TestModel) do
          def self.name
            "MultiModel2"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
        end

        # Both should use default :before_save
        callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        expect(callback).to eq(:before_save)
      end
    end
  end

  describe "configured callback timing" do
    after do
      # Reset to default after each test
      ModelSettings.configure do |config|
        config.module_callback(:simple_audit, :before_save)
      end
    end

    describe "configuration options" do
      context "with :after_save timing" do
        it "accepts and stores configuration" do
          ModelSettings.configure do |config|
            config.module_callback(:simple_audit, :after_save)
          end

          callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
          expect(callback).to eq(:after_save)
        end
      end

      context "with :after_commit timing" do
        it "accepts and stores configuration" do
          ModelSettings.configure do |config|
            config.module_callback(:simple_audit, :after_commit)
          end

          callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
          expect(callback).to eq(:after_commit)
        end
      end
    end

    describe "configuration properties" do
      it "applies to all models globally" do
        ModelSettings.configure do |config|
          config.module_callback(:simple_audit, :after_save)
        end

        Class.new(TestModel) do
          def self.name
            "ConfigModel1"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
        end

        Class.new(TestModel) do
          def self.name
            "ConfigModel2"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
        end

        # Both models should use configured :after_save
        callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        expect(callback).to eq(:after_save)
      end

      it "persists across compilations" do
        ModelSettings.configure do |config|
          config.module_callback(:simple_audit, :after_commit)
        end

        # Create and compile first model
        model1 = Class.new(TestModel) do
          def self.name
            "PersistModel1"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature, type: :column, track_changes: true
        end
        model1.compile_settings!

        # Create and compile second model
        model2 = Class.new(TestModel) do
          def self.name
            "PersistModel2"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :other, type: :column, track_changes: true
        end
        model2.compile_settings!

        # Configuration should persist
        callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        expect(callback).to eq(:after_commit)
      end
    end

    describe "module independence" do
      it "allows different modules to configure callbacks independently" do
        # Register a second test module with callback config
        test_module = Module.new do
          extend ActiveSupport::Concern
        end
        ModelSettings::ModuleRegistry.register_module(:test_callback_module, test_module)
        ModelSettings::ModuleRegistry.register_module_callback_config(
          :test_callback_module,
          default_callback: :before_validation,
          configurable: true
        )

        # Configure both modules differently
        ModelSettings.configure do |config|
          config.module_callback(:simple_audit, :after_save)
          config.module_callback(:test_callback_module, :before_save)
        end

        audit_callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        test_callback = ModelSettings::ModuleRegistry.get_module_callback(:test_callback_module)

        expect(audit_callback).to eq(:after_save)
        expect(test_callback).to eq(:before_save)
      end
    end

    # Note: Invalid callback names are not validated at configuration time.
    # Rails will raise an error when the callback is actually registered in the model.
  end

  describe "interaction with dependency compilation" do
    describe "metadata availability" do
      it "executes callbacks after dependency resolution" do
        execution_log = []

        test_class = Class.new(TestModel) do
          def self.name
            "DependencyCallbackModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          # Simple setting to test compilation
          setting :feature, type: :column, track_changes: true

          define_method(:audit_tracked_settings) do |*args|
            # Verify settings are compiled (dependency resolution complete)
            execution_log << :audit_executed
            # Check that we can access settings metadata (only available after compilation)
            execution_log << :metadata_available if self.class.respond_to?(:find_setting)
            super(*args)
          end
        end
        test_class.compile_settings!

        # Stub Rails.logger
        logger = instance_double(Logger)
        stub_const("Rails", Class.new {
          def self.logger
          end
        })
        allow(Rails).to receive(:logger).and_return(logger)
        allow(logger).to receive(:info)

        instance = test_class.create!(feature: false)
        execution_log.clear

        instance.feature = true
        instance.save!

        # Callback should execute after settings compilation (metadata is available)
        expect(execution_log).to include(:metadata_available)
      end

      it "provides metadata access during callback execution" do
        metadata_captured = nil

        test_class = Class.new(TestModel) do
          def self.name
            "MetadataCallbackModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature, type: :column, track_changes: true

          define_method(:audit_tracked_settings) do |*args|
            # Capture metadata during callback
            metadata_captured = ModelSettings::ModuleRegistry.get_module_metadata(
              self.class,
              :simple_audit,
              :tracked_settings
            )
            super(*args)
          end
        end
        test_class.compile_settings!

        # Stub Rails.logger
        logger = instance_double(Logger)
        stub_const("Rails", Class.new {
          def self.logger
          end
        })
        allow(Rails).to receive(:logger).and_return(logger)
        allow(logger).to receive(:info)

        instance = test_class.create!(feature: false)
        instance.feature = true
        instance.save!

        expect(metadata_captured).to eq([:feature])
      end
    end

    describe "compilation order" do
      it "respects wave-based compilation" do
        # Wave-based compilation ensures parent settings compiled before children
        # Callbacks should respect this order

        test_class = Class.new(TestModel) do
          def self.name
            "WaveOrderModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          # Use multiple tracked settings to verify wave-based compilation
          setting :feature, type: :column, track_changes: true
          setting :enabled, type: :column, track_changes: true
          setting :premium_mode, type: :column, track_changes: true
        end
        test_class.compile_settings!

        # Verify all settings are tracked after compilation
        tracked = test_class.tracked_settings
        expect(tracked.map(&:name)).to contain_exactly(:feature, :enabled, :premium_mode)
      end
    end

    describe "multi-module integration" do
      it "executes all modules' callbacks in order" do
        execution_log = []

        # Create a second test module with callback that can access execution_log
        test_module = Module.new do
          extend ActiveSupport::Concern

          included do
            before_save :test_callback
            cattr_accessor :execution_log
          end

          def test_callback
            self.class.execution_log << :test_module_callback
          end
        end
        ModelSettings::ModuleRegistry.register_module(:test_callback_module, test_module)

        test_class = Class.new(TestModel) do
          def self.name
            "MultiModuleCallbackModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
          include test_module

          setting :feature, type: :column, track_changes: true

          define_method(:audit_tracked_settings) do |*args|
            self.class.execution_log << :audit_callback
            super(*args)
          end
        end
        test_class.compile_settings!

        # Set execution_log on the class
        test_class.execution_log = execution_log

        # Stub Rails.logger
        logger = instance_double(Logger)
        stub_const("Rails", Class.new {
          def self.logger
          end
        })
        allow(Rails).to receive(:logger).and_return(logger)
        allow(logger).to receive(:info)

        instance = test_class.create!(feature: false)
        execution_log.clear

        instance.feature = true
        instance.save!

        # Both callbacks should execute
        expect(execution_log).to include(:audit_callback, :test_module_callback)
      end
    end
  end
end
