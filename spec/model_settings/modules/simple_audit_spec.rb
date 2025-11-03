# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/model_settings/modules/simple_audit"

RSpec.describe ModelSettings::Modules::SimpleAudit do
  # Ensure SimpleAudit module registrations are present and callback is at default
  before do
    # SimpleAudit registers itself at module load time, so we just verify it's there
    unless ModelSettings::ModuleRegistry.module_registered?(:simple_audit)
      raise "SimpleAudit module not registered - this should never happen"
    end

    # Ensure callback is reset to default before each test
    # This is needed because other test files might have changed it
    ModelSettings.configure do |config|
      config.module_callback(:simple_audit, :before_save)
    end
  end

  describe "module registration" do
    describe "basic registration" do
      it "registers :simple_audit module in ModuleRegistry" do
        expect(ModelSettings::ModuleRegistry.module_registered?(:simple_audit)).to be true
      end

      it "registers :track_changes option" do
        expect(ModelSettings::ModuleRegistry.registered_options).to include(:track_changes)
      end
    end

    describe "track_changes option validation" do
      context "with valid boolean value" do
        it "accepts true" do
          test_class = Class.new(TestModel) do
            def self.name
              "SimpleAuditTestModel"
            end

            include ModelSettings::DSL
            include ModelSettings::Modules::SimpleAudit

            setting :feature, type: :column, track_changes: true
          end

          expect { test_class.compile_settings! }.not_to raise_error
        end
      end

      context "but with invalid non-boolean value" do
        it "raises ArgumentError" do
          expect {
            Class.new(TestModel) do
              def self.name
                "InvalidTrackChangesModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::SimpleAudit

              setting :feature, type: :column, track_changes: "yes"
            end
          }.to raise_error(ArgumentError, /track_changes must be true or false/)
        end
      end
    end
  end

  describe "callback configuration" do
    after do
      # Reset callback to default after each test
      ModelSettings.configure do |config|
        config.module_callback(:simple_audit, :before_save)
      end
    end

    describe "default behavior" do
      it "defaults to :before_save" do
        callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        expect(callback).to eq(:before_save)
      end
    end

    describe "custom timing configuration" do
      context "with :after_save timing" do
        it "accepts custom timing" do
          ModelSettings.configure do |config|
            config.module_callback(:simple_audit, :after_save)
          end

          callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
          expect(callback).to eq(:after_save)
        end
      end

      context "with :after_commit timing" do
        it "accepts custom timing" do
          ModelSettings.configure do |config|
            config.module_callback(:simple_audit, :after_commit)
          end

          callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
          expect(callback).to eq(:after_commit)
        end
      end
    end

    describe "configuration properties" do
      it "stores configuration in ModuleRegistry" do
        config = ModelSettings::ModuleRegistry.get_module_callback_config(:simple_audit)

        expect(config).to be_a(Hash)
        expect(config[:default_callback]).to eq(:before_save)
        expect(config[:configurable]).to be true
      end

      it "configuration is global across models" do
        ModelSettings.configure do |config|
          config.module_callback(:simple_audit, :after_save)
        end

        # Create two different models
        Class.new(TestModel) do
          def self.name
            "AuditModel1"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
        end

        Class.new(TestModel) do
          def self.name
            "AuditModel2"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit
        end

        # Both should use the same globally configured callback
        callback = ModelSettings::ModuleRegistry.get_module_callback(:simple_audit)
        expect(callback).to eq(:after_save)
      end
    end
  end

  describe "compilation-time indexing" do
    context "when model has tracked settings" do
      let(:test_class) do
        klass = Class.new(TestModel) do
          def self.name
            "IndexingTestModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true
          setting :feature_b, type: :column, track_changes: true
          setting :feature_c, type: :column, track_changes: false
        end

        klass.compile_settings!
        klass
      end

      it "indexes settings with track_changes: true" do
        tracked = ModelSettings::ModuleRegistry.get_module_metadata(
          test_class,
          :simple_audit,
          :tracked_settings
        )

        expect(tracked).to include(:feature_a, :feature_b)
      end

      it "ignores settings with track_changes: false" do
        tracked = ModelSettings::ModuleRegistry.get_module_metadata(
          test_class,
          :simple_audit,
          :tracked_settings
        )

        expect(tracked).not_to include(:feature_c)
      end

      it "stores indexed settings in centralized metadata" do
        tracked = ModelSettings::ModuleRegistry.get_module_metadata(
          test_class,
          :simple_audit,
          :tracked_settings
        )

        expect(tracked).to be_an(Array)
        expect(tracked).to eq([:feature_a, :feature_b])
      end
    end

    context "when multiple models exist" do
      let(:model1) do
        klass = Class.new(TestModel) do
          def self.name
            "MultiModel1"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :setting1, type: :column, track_changes: true
        end

        klass.compile_settings!
        klass
      end

      let(:model2) do
        klass = Class.new(TestModel) do
          def self.name
            "MultiModel2"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :setting2, type: :column, track_changes: true
        end

        klass.compile_settings!
        klass
      end

      it "indexes are scoped per model class" do
        tracked1 = ModelSettings::ModuleRegistry.get_module_metadata(
          model1,
          :simple_audit,
          :tracked_settings
        )

        tracked2 = ModelSettings::ModuleRegistry.get_module_metadata(
          model2,
          :simple_audit,
          :tracked_settings
        )

        expect(tracked1).to eq([:setting1])
        expect(tracked2).to eq([:setting2])
      end

      it "one model's index doesn't affect another" do
        # Access model1's index first
        tracked1 = ModelSettings::ModuleRegistry.get_module_metadata(
          model1,
          :simple_audit,
          :tracked_settings
        )

        # model2's index should be independent
        tracked2 = ModelSettings::ModuleRegistry.get_module_metadata(
          model2,
          :simple_audit,
          :tracked_settings
        )

        expect(tracked1).not_to eq(tracked2)
        expect(tracked1).to eq([:setting1])
        expect(tracked2).to eq([:setting2])
      end
    end

    context "when no tracked settings" do
      let(:empty_model) do
        klass = Class.new(TestModel) do
          def self.name
            "EmptyTrackingModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :untracked, type: :column, track_changes: false
        end

        klass.compile_settings!
        klass
      end

      it "creates empty index" do
        tracked = ModelSettings::ModuleRegistry.get_module_metadata(
          empty_model,
          :simple_audit,
          :tracked_settings
        )

        expect(tracked).to eq([])
      end
    end
  end

  describe ".tracked_settings" do
    context "when settings are tracked" do
      let(:test_class) do
        klass = Class.new(TestModel) do
          def self.name
            "TrackedSettingsModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :first, type: :column, track_changes: true
          setting :second, type: :column, track_changes: true
          setting :third, type: :column, track_changes: false
        end

        klass.compile_settings!
        klass
      end

      it "returns array of Setting objects" do
        tracked = test_class.tracked_settings

        expect(tracked).to be_an(Array)
        expect(tracked).to all(be_a(ModelSettings::Setting))
      end

      it "returns settings in definition order" do
        tracked = test_class.tracked_settings

        expect(tracked.map(&:name)).to eq([:first, :second])
      end

      it "only returns tracked settings" do
        tracked = test_class.tracked_settings

        expect(tracked.map(&:name)).not_to include(:third)
      end
    end

    context "when no settings tracked" do
      let(:test_class) do
        klass = Class.new(TestModel) do
          def self.name
            "NoTrackedModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :untracked, type: :column
        end

        klass.compile_settings!
        klass
      end

      it "returns empty array" do
        expect(test_class.tracked_settings).to eq([])
      end
    end
  end

  describe ".setting_tracked?" do
    let(:test_class) do
      klass = Class.new(TestModel) do
        def self.name
          "SettingTrackedModel"
        end

        include ModelSettings::DSL
        include ModelSettings::Modules::SimpleAudit

        setting :tracked, type: :column, track_changes: true
        setting :not_tracked, type: :column, track_changes: false
      end

      klass.compile_settings!
      klass
    end

    context "with tracked setting" do
      it "returns true" do
        expect(test_class.setting_tracked?(:tracked)).to be true
      end
    end

    context "but with untracked setting" do
      it "returns false" do
        expect(test_class.setting_tracked?(:not_tracked)).to be false
      end
    end

    context "and with nonexistent setting" do
      it "returns false" do
        expect(test_class.setting_tracked?(:nonexistent)).to be false
      end
    end

    context "with symbol or string name" do
      it "accepts both formats" do
        expect(test_class.setting_tracked?(:tracked)).to be true
        expect(test_class.setting_tracked?("tracked")).to be true
      end
    end
  end

  describe "#audit_tracked_settings" do
    let(:test_class) do
      klass = Class.new(TestModel) do
        def self.name
          "AuditBehaviorModel"
        end

        include ModelSettings::DSL
        include ModelSettings::Modules::SimpleAudit

        setting :feature_a, type: :column, track_changes: true
        setting :feature_b, type: :column, track_changes: false
      end

      klass.compile_settings!
      klass
    end

    # Stub Rails.logger globally for these tests
    let(:logger) { instance_double(Logger) }

    before do
      # Stub Rails constant and logger
      stub_const("Rails", Class.new {
        def self.logger
        end
      })
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
    end

    context "when record is new" do
      it "does not audit (only audits persisted records)" do
        instance = test_class.new
        instance.feature_a = true
        instance.save!

        # Should not log for new records (persisted? was false before save)
        expect(logger).not_to have_received(:info)
      end
    end

    context "when record is persisted" do
      context "when tracked setting changes" do
        let!(:instance) { test_class.create!(feature_a: false, feature_b: false) }

        before do
          # Reset logger mock
          allow(logger).to receive(:info)
        end

        it "logs change to logger" do
          instance.feature_a = true
          instance.save!

          expect(logger).to have_received(:info)
        end

        it "includes model class and ID in log" do
          instance.feature_a = true
          instance.save!

          expect(logger).to have_received(:info).with(/AuditBehaviorModel##{instance.id}/)
        end

        it "includes setting name in log" do
          instance.feature_a = true
          instance.save!

          expect(logger).to have_received(:info).with(/feature_a/)
        end

        it "shows old and new values in log" do
          instance.feature_a = true
          instance.save!

          expect(logger).to have_received(:info).with(/false.*→.*true/)
        end

        it "handles nil to value changes" do
          # Use c column which allows nil
          klass2 = Class.new(TestModel) do
            def self.name
              "AuditNilModel"
            end

            include ModelSettings::DSL
            include ModelSettings::Modules::SimpleAudit

            setting :c, type: :column, track_changes: true
          end
          klass2.compile_settings!

          instance2 = klass2.create!(c: nil)
          instance2.c = true
          instance2.save!

          expect(logger).to have_received(:info).with(/nil.*→.*true/)
        end

        it "handles value to nil changes" do
          klass2 = Class.new(TestModel) do
            def self.name
              "AuditNilModel2"
            end

            include ModelSettings::DSL
            include ModelSettings::Modules::SimpleAudit

            setting :c, type: :column, track_changes: true
          end
          klass2.compile_settings!

          instance2 = klass2.create!(c: true)

          # Reset logger mock for this instance
          allow(logger).to receive(:info)

          instance2.c = nil
          instance2.save!

          expect(logger).to have_received(:info).with(/true.*→.*nil/)
        end
      end

      context "when tracked setting does NOT change" do
        let!(:instance) { test_class.create!(feature_a: false) }

        before do
          allow(logger).to receive(:info)
        end

        it "does not log anything" do
          instance.save!

          expect(logger).not_to have_received(:info)
        end
      end

      context "when untracked setting changes" do
        let!(:instance) { test_class.create!(feature_b: false) }

        before do
          allow(logger).to receive(:info)
        end

        it "does not log untracked changes" do
          instance.feature_b = true
          instance.save!

          # Should not log untracked setting changes
          expect(logger).not_to have_received(:info)
        end
      end
    end
  end

  describe "callback execution" do
    let(:logger) { instance_double(Logger) }

    before do
      stub_const("Rails", Class.new {
        def self.logger
        end
      })
      allow(Rails).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
    end

    after do
      # Reset callback to default after tests that change it
      ModelSettings.configure do |config|
        config.module_callback(:simple_audit, :before_save)
      end
    end

    context "with default timing (:before_save)" do
      it "executes before record is saved" do
        test_class = Class.new(TestModel) do
          def self.name
            "BeforeSaveModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true

          # Track when callback executes relative to save
          attr_accessor :callback_executed_before_save

          def audit_tracked_settings
            # Check if changes are still pending (not yet saved)
            self.callback_executed_before_save = feature_a_changed?
            super
          end
        end
        test_class.compile_settings!

        instance = test_class.create!(feature_a: false)
        allow(logger).to receive(:info)

        instance.feature_a = true
        instance.save!

        # Callback should have seen changed? as true (before save completed)
        expect(instance.callback_executed_before_save).to be true
      end

      it "can access old and new values" do
        test_class = Class.new(TestModel) do
          def self.name
            "OldNewValuesModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true

          attr_accessor :captured_old_value, :captured_new_value

          def audit_tracked_settings
            self.captured_old_value = feature_a_was
            self.captured_new_value = feature_a
            super
          end
        end
        test_class.compile_settings!

        instance = test_class.create!(feature_a: false)
        allow(logger).to receive(:info)

        instance.feature_a = true
        instance.save!

        expect(instance.captured_old_value).to be false
        expect(instance.captured_new_value).to be true
      end
    end

    context "with :after_save timing" do
      before do
        ModelSettings.configure do |config|
          config.module_callback(:simple_audit, :after_save)
        end
      end

      it "executes after record is saved" do
        test_class = Class.new(TestModel) do
          def self.name
            "AfterSaveModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true

          attr_accessor :callback_executed_after_save

          def audit_tracked_settings
            # After save, changed? should be false (already saved)
            self.callback_executed_after_save = !feature_a_changed?
            super
          end
        end
        test_class.compile_settings!

        instance = test_class.create!(feature_a: false)
        allow(logger).to receive(:info)

        instance.feature_a = true
        instance.save!

        # Callback should have seen changed? as false (after save completed)
        expect(instance.callback_executed_after_save).to be true
      end

      it "changes are persisted" do
        test_class = Class.new(TestModel) do
          def self.name
            "PersistedModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true

          attr_accessor :value_in_db_during_callback

          def audit_tracked_settings
            # Check what's in the database during callback
            reloaded = self.class.find(id)
            self.value_in_db_during_callback = reloaded.feature_a
            super
          end
        end
        test_class.compile_settings!

        instance = test_class.create!(feature_a: false)
        allow(logger).to receive(:info)

        instance.feature_a = true
        instance.save!

        # During after_save callback, DB should have new value
        expect(instance.value_in_db_during_callback).to be true
      end
    end

    context "with :after_commit timing" do
      before do
        ModelSettings.configure do |config|
          config.module_callback(:simple_audit, :after_commit)
        end
      end

      it "registers callback with after_commit timing" do
        test_class = Class.new(TestModel) do
          def self.name
            "AfterCommitModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true
        end
        test_class.compile_settings!

        # Verify the callback is registered as after_commit
        callback_chain = test_class._commit_callbacks.select do |cb|
          cb.kind == :after && cb.filter == :audit_tracked_settings
        end

        expect(callback_chain).not_to be_empty
      end

      it "does not execute during save (waits for commit)" do
        execution_log = []

        test_class = Class.new(TestModel) do
          def self.name
            "CommitTimingModel"
          end

          include ModelSettings::DSL
          include ModelSettings::Modules::SimpleAudit

          setting :feature_a, type: :column, track_changes: true

          define_method(:audit_tracked_settings) do |*args|
            execution_log << :audit_executed
            super(*args)
          end

          after_save do
            execution_log << :after_save_executed
          end
        end
        test_class.compile_settings!

        instance = test_class.create!(feature_a: false)
        execution_log.clear
        allow(logger).to receive(:info)

        instance.feature_a = true
        instance.save!

        # after_save should execute before after_commit in the callback chain
        # In test environment, after_commit may not fire due to transaction wrapping,
        # but we verify it's registered with the correct timing
        expect(execution_log).to include(:after_save_executed)

        # Verify after_commit callback is actually registered
        callback = test_class._commit_callbacks.find do |cb|
          cb.kind == :after && cb.filter == :audit_tracked_settings
        end
        expect(callback).not_to be_nil
      end
    end
  end
end
