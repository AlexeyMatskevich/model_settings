# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::DependencyEngine do
  # Test model setup
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "DependencyTestModel"
      end

      include ModelSettings::DSL
    end
  end

  let(:engine) { described_class.new(model_class) }

  describe "#compile!" do
    context "when there are NO sync relationships" do
      before do
        model_class.setting :feature_a, type: :column, default: false
        model_class.setting :feature_b, type: :column, default: false
      end

      it "completes without errors" do
        expect { engine.compile! }.not_to raise_error
      end

      it "builds empty sync execution order" do
        engine.compile!
        expect(engine.sync_execution_order).to be_empty
      end
    end

    context "when sync relationships exist" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :forward}
        model_class.setting :target, type: :column, default: false
      end

      it "completes without errors" do
        expect { engine.compile! }.not_to raise_error
      end

      it "builds sync execution order" do
        engine.compile!
        expect(engine.sync_execution_order).not_to be_empty
      end
    end
  end

  describe "#validate_sync_graph!" do
    context "when there are NO cycles" do
      before do
        model_class.setting :a, type: :column, default: false, sync: {target: :b, mode: :forward}
        model_class.setting :b, type: :column, default: false, sync: {target: :c, mode: :forward}
        model_class.setting :c, type: :column, default: false
      end

      it "does NOT raise error" do
        expect { engine.validate_sync_graph! }.not_to raise_error
      end

      it "builds topological order" do
        engine.validate_sync_graph!

        setting_names = engine.sync_execution_order.map(&:name)
        a_idx = setting_names.index(:a)
        b_idx = setting_names.index(:b)

        expect(a_idx).to be < b_idx
      end
    end

    context "when there is a simple cycle" do
      before do
        model_class.setting :a, type: :column, default: false, sync: {target: :b, mode: :forward}
        model_class.setting :b, type: :column, default: false, sync: {target: :a, mode: :forward}
      end

      it "raises CyclicSyncError" do
        expect { engine.validate_sync_graph! }.to raise_error(ModelSettings::CyclicSyncError)
      end

      it "includes cycle information in error message" do
        expect { engine.validate_sync_graph! }
          .to raise_error(ModelSettings::CyclicSyncError, /Cyclic sync detected/)
      end
    end

    context "when there is a complex cycle" do
      before do
        model_class.setting :a, type: :column, default: false, sync: {target: :b, mode: :forward}
        model_class.setting :b, type: :column, default: false, sync: {target: :c, mode: :forward}
        model_class.setting :c, type: :column, default: false, sync: {target: :a, mode: :forward}
      end

      it "raises CyclicSyncError" do
        expect { engine.validate_sync_graph! }.to raise_error(ModelSettings::CyclicSyncError)
      end
    end

    context "when there are disconnected components" do
      before do
        model_class.setting :a, type: :column, default: false, sync: {target: :b, mode: :forward}
        model_class.setting :b, type: :column, default: false
        model_class.setting :c, type: :column, default: false, sync: {target: :d, mode: :forward}
        model_class.setting :d, type: :column, default: false
      end

      it "does NOT raise error" do
        expect { engine.validate_sync_graph! }.not_to raise_error
      end

      it "includes settings with sync configurations in execution order" do
        engine.validate_sync_graph!

        setting_names = engine.sync_execution_order.map(&:name)
        expect(setting_names).to include(:a, :c)
      end
    end
  end

  describe "#execute_cascades_and_syncs" do
    # rubocop:disable RSpecGuide/DuplicateLetValues, RSpec/MultipleExpectations
    # Each context needs fresh instance with different settings configuration
    # Multiple expectations needed for interface testing (cascade affects multiple children, chain propagates through multiple syncs)
    context "when there are NO cascades or syncs" do
      before do
        model_class.setting :feature, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      it "does NOT modify instance" do
        setting = model_class.find_setting(:feature)
        instance.feature = true

        expect { engine.execute_cascades_and_syncs(instance, [setting]) }
          .not_to change(instance, :feature)
      end
    end

    context "with enable cascade" do
      before do
        model_class.setting :parent, type: :column, default: false, cascade: {enable: true} do
          setting :child_a, type: :column, default: false
          setting :child_b, type: :column, default: false
        end
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "when parent is enabled" do
        before do
          instance.parent = true
        end

        it "enables all children" do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be true
          expect(instance.child_b).to be true
        end
      end

      context "when parent is disabled" do
        before do
          instance.parent = false
        end

        it "does NOT change children" do
          parent_setting = model_class.find_setting(:parent)

          expect { engine.execute_cascades_and_syncs(instance, [parent_setting]) }
            .not_to change { [instance.child_a, instance.child_b] }
        end
      end

      context "when children are already enabled" do
        before do
          instance.update!(parent: false, child_a: true, child_b: true)
          instance.parent = true
        end

        it "keeps children enabled" do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be true
          expect(instance.child_b).to be true
        end
      end
    end

    context "with disable cascade" do
      before do
        model_class.setting :parent, type: :column, default: true, cascade: {disable: true} do
          setting :child_a, type: :column, default: true
          setting :child_b, type: :column, default: true
        end
        model_class.compile_settings!
      end

      let(:instance) do
        inst = model_class.create!
        inst.update!(parent: true, child_a: true, child_b: true)
        inst
      end

      context "when parent is disabled" do
        before do
          instance.parent = false
        end

        it "disables all children" do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be false
          expect(instance.child_b).to be false
        end
      end

      context "when parent is enabled" do
        before do
          instance.parent = true
        end

        it "does NOT change children" do
          parent_setting = model_class.find_setting(:parent)

          expect { engine.execute_cascades_and_syncs(instance, [parent_setting]) }
            .not_to change { [instance.child_a, instance.child_b] }
        end
      end

      context "when children are already disabled" do
        before do
          instance.update!(parent: true, child_a: false, child_b: false)
          instance.parent = false
        end

        it "keeps children disabled" do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be false
          expect(instance.child_b).to be false
        end
      end
    end

    context "with both enable and disable cascades" do
      before do
        model_class.setting :parent, type: :column, default: false, cascade: {enable: true, disable: true} do
          setting :child, type: :column, default: false
        end
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      it "propagates enable to children" do
        instance.parent = true
        parent_setting = model_class.find_setting(:parent)

        engine.execute_cascades_and_syncs(instance, [parent_setting])
        expect(instance.child).to be true
      end

      it "propagates disable to children" do
        instance.update!(parent: true, child: true)
        instance.parent = false
        parent_setting = model_class.find_setting(:parent)

        engine.execute_cascades_and_syncs(instance, [parent_setting])
        expect(instance.child).to be false
      end
    end

    context "with forward sync" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :forward}
        model_class.setting :target, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      # rubocop:disable RSpecGuide/ContextSetup, RSpecGuide/DuplicateBeforeHooks
      # First context is happy path without additional setup
      # Duplicate before hooks test different scenarios (false->true vs already matching)
      context "when source changes to true" do
        it "sets target to true" do
          instance.source = true
          instance.save!

          expect(instance.reload.target).to be true
        end
      end

      context "when source changes to false" do
        before do
          instance.update!(source: true, target: true)
        end

        it "sets target to false" do
          instance.source = false
          instance.save!

          expect(instance.reload.target).to be false
        end
      end

      context "when target already matches source" do
        before do
          instance.update!(source: true, target: true)
        end

        it "does NOT mark target as changed after save" do
          instance.source = true
          instance.save!

          expect(instance.target_changed?).to be false
        end
      end
      # rubocop:enable RSpecGuide/ContextSetup, RSpecGuide/DuplicateBeforeHooks
    end

    context "with inverse sync" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :inverse}
        model_class.setting :target, type: :column, default: true
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      # rubocop:disable RSpecGuide/ContextSetup
      # First context is happy path without additional setup
      context "when source is true" do
        it "sets target to false" do
          instance.source = true
          instance.save!

          expect(instance.reload.target).to be false
        end
      end

      context "when source is false" do
        before do
          instance.update!(source: true, target: false)
        end

        it "sets target to true" do
          instance.source = false
          instance.save!

          expect(instance.reload.target).to be true
        end
      end

      context "when target already matches inverse of source" do
        before do
          instance.update!(source: false, target: true)
        end

        it "does NOT mark target as changed after save" do
          instance.source = false
          instance.save!

          expect(instance.target_changed?).to be false
        end
      end
      # rubocop:enable RSpecGuide/ContextSetup
    end

    context "with backward sync" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :backward}
        model_class.setting :target, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "when source changes" do
        before do
          instance.update!(source: false, target: true)
        end

        it "reverts source to match target" do
          instance.source = true
          instance.save!

          expect(instance.reload.source).to be true
        end
      end
    end

    context "with chained syncs" do
      before do
        model_class.setting :a, type: :column, default: false, sync: {target: :b, mode: :forward}
        model_class.setting :b, type: :column, default: false, sync: {target: :c, mode: :forward}
        model_class.setting :c, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      it "propagates changes through chain" do
        instance.a = true
        instance.save!

        instance.reload
        expect(instance.b).to be true
        expect(instance.c).to be true
      end
    end

    context "with both cascades and syncs in same transaction" do
      before do
        # Parent with cascade to child_a
        model_class.setting :parent, type: :column, default: false, cascade: {enable: true} do
          setting :child_a, type: :column, default: false
        end
        # Independent sync from source to target
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :forward}
        model_class.setting :target, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      it "applies both cascade and sync in same save" do
        instance.parent = true
        instance.source = true
        instance.save!

        instance.reload
        expect(instance.child_a).to be true
        expect(instance.target).to be true
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup, RSpec/ExampleLength
    # Context contains two independent tests without shared setup
    # Second test requires complex stubbing setup (>10 lines justified)
    context "when max iterations reached" do
      it "has MAX_ITERATIONS safety limit" do
        expect(described_class::MAX_ITERATIONS).to eq(100)
      end

      it "raises error with stubbed infinite cascade" do
        model_class.setting :feature, type: :column, default: false
        model_class.compile_settings!

        instance = model_class.create!
        initial_setting = model_class.find_setting(:feature)

        # Create fake settings to bypass all_processed check
        counter = 0
        allow(engine).to receive(:apply_cascades_batch) do
          counter += 1
          # Create new fake setting each time to avoid all_processed filtering
          [ModelSettings::Setting.new(:"fake_#{counter}", {})]
        end
        allow(engine).to receive(:apply_syncs_batch).and_return([])

        expect { engine.execute_cascades_and_syncs(instance, [initial_setting]) }
          .to raise_error(/Infinite cascade detected/)
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup, RSpec/ExampleLength
    # rubocop:enable RSpecGuide/DuplicateLetValues, RSpec/MultipleExpectations
  end

  describe "#extract_storage_columns" do
    context "with column storage" do
      before do
        model_class.setting :feature_a, type: :column, default: false
        model_class.setting :feature_b, type: :column, default: false
      end

      it "extracts column names" do
        engine.compile!

        expect(model_class::SETTINGS_COLUMNS).to contain_exactly(:feature_a, :feature_b)
      end
    end

    context "with JSON storage" do
      before do
        model_class.setting :prefs, type: :json, storage: {column: :preferences} do
          setting :theme, default: "light"
        end
      end

      it "extracts JSON column name" do
        engine.compile!

        expect(model_class::SETTINGS_COLUMNS).to contain_exactly(:preferences)
      end
    end

    context "with mixed storage types" do
      before do
        model_class.setting :enabled, type: :column, default: false
        model_class.setting :prefs, type: :json, storage: {column: :preferences} do
          setting :theme, default: "light"
        end
      end

      it "extracts all unique column names" do
        engine.compile!

        expect(model_class::SETTINGS_COLUMNS).to contain_exactly(:enabled, :preferences)
      end
    end

    context "when SETTINGS_COLUMNS already exists" do
      before do
        model_class.const_set(:SETTINGS_COLUMNS, [:existing])
        model_class.setting :feature, type: :column, default: false
      end

      # rubocop:disable RSpec/MultipleExpectations
      it "does NOT redefine constant" do
        expect { engine.compile! }.not_to raise_error
        expect(model_class::SETTINGS_COLUMNS).to eq([:existing])
      end
      # rubocop:enable RSpec/MultipleExpectations
    end
  end

  # Note: Mixed storage types with nested settings (eg. column parent with JSON child that has own storage)
  # is an advanced edge case that requires additional implementation work.
  # The basic mixed storage (different types at root level) works via cascades/syncs.
  # TODO: Implement full support for nested settings with different storage types
end
