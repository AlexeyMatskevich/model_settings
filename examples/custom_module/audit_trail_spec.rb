# frozen_string_literal: true

# rubocop:disable all
# Example Tests for AuditTrail Module
#
# This file demonstrates how to test a custom ModelSettings module.
# It covers all major aspects: registration, options, hooks, and runtime behavior.
#
# Note: These are example tests. To run them in your application:
# 1. Copy audit_trail.rb to lib/model_settings/modules/
# 2. Create AuditLog model with migration
# 3. Copy this file to spec/model_settings/modules/
# 4. Run: rspec spec/model_settings/modules/audit_trail_spec.rb
#
# RuboCop is disabled for this example file since it's meant for demonstration,
# not production use. Real tests should follow RSpec style guidelines.

require "spec_helper"

RSpec.describe ModelSettings::Modules::AuditTrail do
  # Setup test model
  let(:test_model) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"

      def self.name
        "AuditedModel"
      end

      include ModelSettings::DSL
      include ModelSettings::Modules::AuditTrail
    end
  end

  before do
    # Create in-memory AuditLog model for testing
    stub_const("ModelSettings::Modules::AuditTrail::AuditLog", Class.new(ActiveRecord::Base) do
      self.table_name = "audit_logs"

      # Mock implementation for testing
      def self.create!(attributes)
        new(attributes).tap { |log| log.id = rand(1000) }
      end
    end)
  end

  describe "module registration" do
    it "registers with ModuleRegistry" do
      expect(ModuleRegistry.module_registered?(:audit_trail)).to be true
    end

    it "is included in the test model" do
      expect(ModuleRegistry.module_included?(:audit_trail, test_model)).to be true
    end
  end

  describe "option registration" do
    describe "audit_level option" do
      it "accepts :minimal value" do
        expect {
          test_model.setting :feature, type: :column, audit_level: :minimal
        }.not_to raise_error
      end

      it "accepts :detailed value" do
        expect {
          test_model.setting :feature, type: :column, audit_level: :detailed
        }.not_to raise_error
      end

      it "rejects invalid values" do
        expect {
          test_model.setting :feature, type: :column, audit_level: :invalid
        }.to raise_error(ArgumentError, /audit_level must be :minimal or :detailed/)
      end
    end

    describe "audit_user option" do
      it "accepts callable (Proc)" do
        expect {
          test_model.setting :feature, type: :column, audit_user: proc { "user" }
        }.not_to raise_error
      end

      it "accepts callable (Lambda)" do
        expect {
          test_model.setting :feature, type: :column, audit_user: ->(instance) { "user" }
        }.not_to raise_error
      end

      it "accepts nil" do
        expect {
          test_model.setting :feature, type: :column, audit_user: nil
        }.not_to raise_error
      end

      it "rejects non-callable values" do
        expect {
          test_model.setting :feature, type: :column, audit_user: "not_callable"
        }.to raise_error(ArgumentError, /audit_user must be a callable/)
      end
    end

    describe "audit_if option" do
      it "accepts callable" do
        expect {
          test_model.setting :feature,
            type: :column,
            audit_level: :detailed,
            audit_if: ->(instance) { true }
        }.not_to raise_error
      end

      it "rejects non-callable values" do
        expect {
          test_model.setting :feature, type: :column, audit_if: true
        }.to raise_error(ArgumentError, /audit_if must be a callable/)
      end
    end
  end

  describe "metadata storage" do
    before do
      test_model.setting :premium,
        type: :column,
        audit_level: :detailed,
        audit_user: ->(instance) { "current_user" }
      test_model.compile_settings!
    end

    it "stores metadata for audited settings" do
      meta = ModuleRegistry.get_module_metadata(test_model, :audit_trail, :premium)

      expect(meta).not_to be_nil
      expect(meta[:level]).to eq(:detailed)
      expect(meta[:user_callable]).to be_a(Proc)
    end

    it "does not store metadata for non-audited settings" do
      test_model.setting :regular, type: :column
      test_model.compile_settings!

      meta = ModuleRegistry.get_module_metadata(test_model, :audit_trail, :regular)
      expect(meta).to be_nil
    end
  end

  describe "inheritable options" do
    it "registers audit_level as inheritable" do
      expect(ModuleRegistry.inheritable_option?(:audit_level)).to be true
    end

    it "registers audit_user as inheritable" do
      expect(ModuleRegistry.inheritable_option?(:audit_user)).to be true
    end

    it "uses :replace merge strategy for audit_level" do
      expect(ModuleRegistry.merge_strategy_for(:audit_level)).to eq(:replace)
    end
  end

  describe "callback configuration" do
    it "registers default callback as :after_save" do
      config = ModuleRegistry.get_module_callback_config(:audit_trail)

      expect(config[:default_callback]).to eq(:after_save)
    end

    it "allows callback configuration" do
      config = ModuleRegistry.get_module_callback_config(:audit_trail)

      expect(config[:configurable]).to be true
    end
  end

  describe "query methods registration" do
    it "registers audited_settings method" do
      methods = ModuleRegistry.query_methods_for(:audit_trail)
      method_names = methods.map { |m| m[:method_name] }

      expect(method_names).to include(:audited_settings)
    end

    it "registers audit_history method" do
      methods = ModuleRegistry.query_methods_for(:audit_trail)
      method_names = methods.map { |m| m[:method_name] }

      expect(method_names).to include(:audit_history)
    end
  end

  describe ".audited_settings" do
    before do
      test_model.setting :audited, type: :column, audit_level: :minimal
      test_model.setting :not_audited, type: :column
      test_model.compile_settings!
    end

    it "returns only audited settings" do
      audited = test_model.audited_settings
      names = audited.map(&:name)

      expect(names).to include(:audited)
      expect(names).not_to include(:not_audited)
    end
  end

  describe ".audit_config_for" do
    before do
      test_model.setting :premium, type: :column, audit_level: :detailed
      test_model.compile_settings!
    end

    it "returns configuration for audited setting" do
      config = test_model.audit_config_for(:premium)

      expect(config).not_to be_nil
      expect(config[:level]).to eq(:detailed)
    end

    it "returns nil for non-audited setting" do
      test_model.setting :regular, type: :column
      test_model.compile_settings!

      config = test_model.audit_config_for(:regular)
      expect(config).to be_nil
    end
  end

  describe "#audited?" do
    let(:instance) { test_model.new }

    before do
      test_model.setting :premium, type: :column, audit_level: :minimal
      test_model.setting :regular, type: :column
      test_model.compile_settings!
    end

    it "returns true for audited settings" do
      expect(instance.audited?(:premium)).to be true
    end

    it "returns false for non-audited settings" do
      expect(instance.audited?(:regular)).to be false
    end
  end

  describe "audit logging" do
    let(:instance) { test_model.new }
    let(:audit_log_class) { ModelSettings::Modules::AuditTrail::AuditLog }

    before do
      test_model.setting :premium,
        type: :column,
        default: false,
        audit_level: :detailed,
        audit_user: ->(inst) { inst.instance_variable_get(:@current_user) }
      test_model.compile_settings!

      # Set a mock user
      instance.instance_variable_set(:@current_user, "test_user")
    end

    it "creates audit log when setting changes" do
      expect(audit_log_class).to receive(:create!).with(
        hash_including(
          setting: "premium",
          old_value: false,
          new_value: true,
          level: "detailed"
        )
      )

      instance.premium = true
    end

    context "with minimal audit level" do
      before do
        test_model.setting :feature, type: :column, default: false, audit_level: :minimal
        test_model.compile_settings!
      end

      it "does not log old/new values" do
        expect(audit_log_class).to receive(:create!).with(
          hash_including(
            setting: "feature",
            old_value: nil,
            new_value: nil,
            level: "minimal"
          )
        )

        instance.feature = true
      end
    end

    context "with audit_if condition" do
      before do
        test_model.setting :conditional,
          type: :column,
          default: false,
          audit_level: :detailed,
          audit_if: ->(inst) { inst.instance_variable_get(:@should_audit) }
        test_model.compile_settings!
      end

      it "creates audit log when condition is true" do
        instance.instance_variable_set(:@should_audit, true)

        expect(audit_log_class).to receive(:create!)
        instance.conditional = true
      end

      it "skips audit log when condition is false" do
        instance.instance_variable_set(:@should_audit, false)

        expect(audit_log_class).not_to receive(:create!)
        instance.conditional = true
      end
    end
  end

  describe "inheritance behavior" do
    before do
      test_model.setting :billing, audit_level: :detailed do
        setting :invoices, type: :column
        setting :reports, type: :column, audit_level: :minimal  # Override
      end
      test_model.compile_settings!
    end

    it "inherits audit_level to child without explicit value" do
      meta = ModuleRegistry.get_module_metadata(test_model, :audit_trail, :invoices)
      expect(meta).to be_nil  # Inherits from parent, but parent is not a column setting
    end

    it "allows child to override inherited audit_level" do
      meta = ModuleRegistry.get_module_metadata(test_model, :audit_trail, :reports)
      expect(meta[:level]).to eq(:minimal)
    end
  end
end
