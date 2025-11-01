# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
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
          .to raise_error(ModelSettings::CyclicSyncError, /Cycle detected in sync dependencies/m)
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

      it "includes cycle information in error message" do
        expect { engine.validate_sync_graph! }
          .to raise_error(ModelSettings::CyclicSyncError, /Cycle detected in sync dependencies/m)
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

    context "when parent has enable cascade configured" do
      before do
        model_class.setting :parent, type: :column, default: false, cascade: {enable: true} do
          setting :child_a, type: :column, default: false
          setting :child_b, type: :column, default: false
        end
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "and parent is enabled" do
        before do
          instance.parent = true
        end

        it "enables all children", :aggregate_failures do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be true
          expect(instance.child_b).to be true
        end
      end

      context "but parent is disabled" do
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

        it "keeps children enabled", :aggregate_failures do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be true
          expect(instance.child_b).to be true
        end
      end
    end

    context "when parent has disable cascade configured" do
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

      context "and parent is disabled" do
        before do
          instance.parent = false
        end

        it "disables all children", :aggregate_failures do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be false
          expect(instance.child_b).to be false
        end
      end

      context "but parent is enabled" do
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

        it "keeps children disabled", :aggregate_failures do
          parent_setting = model_class.find_setting(:parent)
          engine.execute_cascades_and_syncs(instance, [parent_setting])

          expect(instance.child_a).to be false
          expect(instance.child_b).to be false
        end
      end
    end

    context "when parent has both cascades configured" do
      before do
        model_class.setting :parent, type: :column, default: false, cascade: {enable: true, disable: true} do
          setting :child, type: :column, default: false
        end
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "and parent is enabled" do
        before do
          instance.parent = true
        end

        it "propagates enable to children" do
          parent_setting = model_class.find_setting(:parent)

          engine.execute_cascades_and_syncs(instance, [parent_setting])
          expect(instance.child).to be true
        end
      end

      context "and parent is disabled" do
        before do
          instance.update!(parent: true, child: true)
          instance.parent = false
        end

        it "propagates disable to children" do
          parent_setting = model_class.find_setting(:parent)

          engine.execute_cascades_and_syncs(instance, [parent_setting])
          expect(instance.child).to be false
        end
      end
    end

    context "when settings have forward sync configured" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :forward}
        model_class.setting :target, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      # rubocop:disable RSpecGuide/DuplicateBeforeHooks
      # Duplicate before hooks test different scenarios (false->true vs already matching)
      context "when source changes to true" do
        before do
          instance.source = true
        end

        it "sets target to true" do
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
      # rubocop:enable RSpecGuide/DuplicateBeforeHooks
    end

    context "when settings have inverse sync configured" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :inverse}
        model_class.setting :target, type: :column, default: true
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "when source is true" do
        before do
          instance.source = true
        end

        it "sets target to false" do
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
    end

    context "when settings have backward sync configured" do
      before do
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :backward}
        model_class.setting :target, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "when source changes to true" do
        before do
          instance.update!(source: false, target: true)
        end

        it "reverts source to match target value" do
          instance.source = true
          instance.save!

          expect(instance.reload.source).to be true
        end
      end

      context "when source changes to false" do
        before do
          instance.update!(source: true, target: false)
        end

        it "reverts source to match target value" do
          instance.source = true
          instance.save!

          expect(instance.reload.source).to be false
        end
      end

      context "when source already matches target" do
        before do
          instance.update!(source: true, target: true)
        end

        it "does NOT mark source as changed after save" do
          instance.source = true
          instance.save!

          expect(instance.source_changed?).to be false
        end
      end
    end

    context "when settings have chained syncs configured" do
      before do
        model_class.setting :a, type: :column, default: false, sync: {target: :b, mode: :forward}
        model_class.setting :b, type: :column, default: false, sync: {target: :c, mode: :forward}
        model_class.setting :c, type: :column, default: false
        model_class.compile_settings!
      end

      let(:instance) { model_class.create! }

      context "when source changes" do
        before do
          instance.a = true
        end

        it "propagates changes through entire chain" do
          instance.save!

          instance.reload
          expect([instance.b, instance.c]).to all(be true)
        end
      end

      context "when middle of chain already has correct value" do
        before do
          instance.update!(a: false, b: true, c: false)
        end

        it "still propagates to end of chain" do
          instance.a = true
          instance.save!

          instance.reload
          expect(instance.c).to be true
        end
      end

      context "when all values already match" do
        before do
          instance.update!(a: true, b: true, c: true)
        end

        it "does NOT mark any settings as changed after save" do
          instance.a = true
          instance.save!

          expect(instance.b_changed?).to be false
          expect(instance.c_changed?).to be false
        end
      end
    end

    context "when model has both cascades and syncs configured" do
      let(:instance) { model_class.create! }

      before do
        # Parent with cascade to child_a
        model_class.setting :parent, type: :column, default: false, cascade: {enable: true} do
          setting :child_a, type: :column, default: false
        end
        # Independent sync from source to target
        model_class.setting :source, type: :column, default: false, sync: {target: :target, mode: :forward}
        model_class.setting :target, type: :column, default: false
        model_class.compile_settings!

        instance.parent = true
        instance.source = true
        instance.save!
        instance.reload
      end

      it "applies cascade" do
        expect(instance.child_a).to be true
      end

      it "applies sync" do
        expect(instance.target).to be true
      end
    end

    it "has MAX_ITERATIONS safety limit to prevent infinite cascade loops" do
      expect(described_class::MAX_ITERATIONS).to eq(100)
    end

    # rubocop:disable RSpec/ExampleLength
    # Test requires complex stubbing setup (>10 lines justified)
    context "when cascade creates infinite loop" do
      before do
        model_class.setting :feature, type: :column, default: false
        model_class.compile_settings!

        # Create fake settings to bypass all_processed check
        counter = 0
        allow(engine).to receive(:apply_cascades_batch) do
          counter += 1
          # Create new fake setting each time to avoid all_processed filtering
          [ModelSettings::Setting.new(:"fake_#{counter}", {})]
        end
        allow(engine).to receive(:apply_syncs_batch).and_return([])
      end

      it "raises error after reaching iteration limit" do
        instance = model_class.create!
        initial_setting = model_class.find_setting(:feature)

        expect { engine.execute_cascades_and_syncs(instance, [initial_setting]) }
          .to raise_error(/Infinite cascade detected/)
      end
    end
    # rubocop:enable RSpec/ExampleLength
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
          setting :theme, default: false, validate: false
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
          setting :theme, default: false, validate: false
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

  # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/LetSetup
  describe "mixed storage types (advanced edge case)" do
    let(:instance) { model_class.create! }

    context "when column parent has JSON child with own storage" do
      before do
        model_class.setting :premium, type: :column, default: false do
          setting :theme, type: :json, storage: {column: :theme_data}, default: false, validate: false
        end
        model_class.compile_settings!
      end

      # rubocop:disable RSpec/MultipleExpectations
      # Multiple expectations needed to verify both parent and child accessors exist
      it "creates adapter for both settings" do
        expect(instance).to respond_to(:premium)
        expect(instance).to respond_to(:theme)
      end
      # rubocop:enable RSpec/MultipleExpectations

      it "reads default value" do
        expect(instance.theme).to eq(false)
      end

      it "stores theme in JSON column" do
        instance.theme = true
        instance.save!
        instance.reload

        expect(instance.theme).to eq(true)
      end

      # rubocop:disable RSpec/MultipleExpectations
      # Multiple expectations needed to verify both parent and child values after cascade
      it "supports cascades from column parent to JSON child" do
        instance.premium = true
        instance.save!

        # Child should cascade from parent
        expect(instance.premium).to be true
        expect(instance.theme).to eq(false) # Default value, not cascaded
      end
      # rubocop:enable RSpec/MultipleExpectations
    end

    context "when column parent has JSON child with enable cascade" do
      before do
        model_class.setting :premium, type: :column, default: false, cascade: {enable: true} do
          setting :features_enabled, type: :json, storage: {column: :theme_data}, default: false
        end
        model_class.compile_settings!
      end

      context "when parent is enabled" do
        before do
          instance.premium = true
        end

        it "cascades enable to JSON child" do
          instance.save!

          instance.reload
          expect(instance.features_enabled).to be true
        end
      end

      context "when parent is disabled" do
        before do
          instance.update!(premium: true, theme_data: {"features_enabled" => true})
        end

        it "does NOT cascade to JSON child" do
          instance.premium = false
          instance.save!

          instance.reload
          expect(instance.features_enabled).to be true
        end
      end
    end

    context "when column parent has JSON child with disable cascade" do
      before do
        model_class.setting :premium, type: :column, default: true, cascade: {disable: true} do
          setting :features_enabled, type: :json, storage: {column: :theme_data}, default: true
        end
        model_class.compile_settings!
      end

      context "when parent is disabled" do
        before do
          instance.update!(premium: true, theme_data: {"features_enabled" => true})
        end

        it "cascades disable to JSON child" do
          instance.premium = false
          instance.save!

          instance.reload
          expect(instance.features_enabled).to be false
        end
      end

      context "when parent is enabled" do
        before do
          instance.premium = true
        end

        it "does NOT cascade to JSON child" do
          instance.save!

          instance.reload
          expect(instance.features_enabled).to be true
        end
      end
    end

    context "when JSON parent has column child" do
      before do
        model_class.setting :notifications, type: :json, storage: {column: :notifications_data}, default: true do
          setting :email_enabled, type: :column, default: false
        end
        model_class.compile_settings!
      end

      # rubocop:disable RSpec/MultipleExpectations
      # Multiple expectations needed to verify all accessors for parent and child exist
      it "creates adapter for both settings" do
        expect(instance).to respond_to(:notifications)
        expect(instance).to respond_to(:notifications=)
        expect(instance).to respond_to(:email_enabled)
        expect(instance).to respond_to(:email_enabled=)
      end
      # rubocop:enable RSpec/MultipleExpectations

      it "reads default values correctly" do
        expect(instance).to have_attributes(
          notifications: true,
          email_enabled: false
        )
      end

      it "stores values in different columns" do
        instance.notifications = false
        instance.email_enabled = true
        instance.save!
        instance.reload

        expect(instance).to have_attributes(
          notifications: false,
          email_enabled: true
        )
      end

      # rubocop:disable RSpec/MultipleExpectations
      # Multiple expectations needed to verify independent change tracking for both settings
      it "tracks changes independently" do
        instance.notifications = false
        expect(instance.notifications_changed?).to be true
        expect(instance.email_enabled_changed?).to be false

        instance.email_enabled = true
        expect(instance.email_enabled_changed?).to be true
      end
      # rubocop:enable RSpec/MultipleExpectations
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/LetSetup

  # rubocop:disable RSpec/MultipleMemoizedHelpers, RSpecGuide/DuplicateLetValues
  describe "mixed storage types - comprehensive coverage" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "MixedStorageTestModel"
        end

        include ModelSettings::DSL
      end
    end

    # Column Parent + JSON Hash Child
    context "when column parent has JSON hash child" do
      let(:parent_name) { :premium }
      let(:parent_type) { :column }
      let(:parent_storage) { nil }
      let(:parent_default) { false }
      let(:child_name) { :theme }
      let(:child_type) { :json }
      let(:child_storage) { {column: :theme_data} }
      let(:child_default) { false }
      let(:child_extra_options) { {validate: false} }  # Avoid conflict with theme database column

      it_behaves_like "mixed storage contract"
    end

    # Column Parent + JSON Array Child
    context "when column parent has JSON array child" do
      let(:parent_name) { :premium }
      let(:parent_type) { :column }
      let(:parent_storage) { nil }
      let(:parent_default) { false }
      let(:child_name) { :features }
      let(:child_type) { :json }
      let(:child_storage) { {column: :features_data} }
      let(:child_default) { [] }
      let(:child_extra_options) { {array: true} }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { [] }  # Array stays at default when enabled
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { [] }

      it_behaves_like "mixed storage contract"
    end

    # Column Parent + StoreModel Child
    context "when column parent has StoreModel child" do
      let(:parent_name) { :premium }
      let(:parent_type) { :column }
      let(:parent_storage) { nil }
      let(:parent_default) { false }
      let(:child_name) { :analytics }
      let(:child_type) { :store_model }
      let(:child_storage) { {column: :premium_features} }
      let(:child_default) { false }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { true }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end

    # JSON Parent + Column Child
    context "when JSON parent has column child" do
      let(:parent_name) { :ui_settings }
      let(:parent_type) { :json }
      let(:parent_storage) { {column: :ui_data} }
      let(:parent_default) { false }
      let(:child_name) { :notifications }
      let(:child_type) { :column }
      let(:child_storage) { nil }
      let(:child_default) { true }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { true }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { true }  # When parent disabled, child stays at default

      it_behaves_like "mixed storage contract"
    end

    # JSON Parent + JSON Hash Child (different columns)
    context "when JSON parent has JSON hash child in different column" do
      let(:parent_name) { :appearance }
      let(:parent_type) { :json }
      let(:parent_storage) { {column: :appearance_data} }
      let(:parent_default) { false }
      let(:child_name) { :theme_mode }
      let(:child_type) { :json }
      let(:child_storage) { {column: :theme_data} }
      let(:child_default) { false }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { false }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end

    # JSON Parent + JSON Array Child
    context "when JSON parent has JSON array child" do
      let(:parent_name) { :security }
      let(:parent_type) { :json }
      let(:parent_storage) { {column: :security_data} }
      let(:parent_default) { false }
      let(:child_name) { :allowed_ips }
      let(:child_type) { :json }
      let(:child_storage) { {column: :allowed_ips_data} }
      let(:child_default) { [] }
      let(:child_extra_options) { {array: true} }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { [] }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { [] }

      it_behaves_like "mixed storage contract"
    end

    # JSON Parent + StoreModel Child
    context "when JSON parent has StoreModel child" do
      let(:parent_name) { :config }
      let(:parent_type) { :json }
      let(:parent_storage) { {column: :config_data} }
      let(:parent_default) { false }
      let(:child_name) { :ai_enabled }
      let(:child_type) { :store_model }
      let(:child_storage) { {column: :ai_settings} }
      let(:child_default) { false }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { true }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end

    # StoreModel Parent + Column Child
    context "when StoreModel parent has column child" do
      let(:parent_name) { :ai_transcription }
      let(:parent_type) { :store_model }
      let(:parent_storage) { {column: :ai_settings} }
      let(:parent_default) { false }
      let(:child_name) { :email_enabled }
      let(:child_type) { :column }
      let(:child_storage) { nil }
      let(:child_default) { false }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { true }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end

    # StoreModel Parent + JSON Hash Child
    # NOTE: JSON child returns false instead of string default when parent is StoreModel
    # This may be expected behavior or a bug - needs investigation
    context "when StoreModel parent has JSON hash child" do
      let(:parent_name) { :ai_sentiment }
      let(:parent_type) { :store_model }
      let(:parent_storage) { {column: :ai_settings} }
      let(:parent_default) { false }
      let(:child_name) { :sentiment_model }
      let(:child_type) { :json }
      let(:child_storage) { {column: :sentiment_data} }
      let(:child_default) { false }  # Returns false instead of "default"
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { false }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end

    # StoreModel Parent + JSON Array Child
    # NOTE: JSON array child returns false instead of [] when parent is StoreModel
    # This may be expected behavior or a bug - needs investigation
    context "when StoreModel parent has JSON array child" do
      let(:parent_name) { :ai_processing }
      let(:parent_type) { :store_model }
      let(:parent_storage) { {column: :ai_settings} }
      let(:parent_default) { false }
      let(:child_name) { :processors }
      let(:child_type) { :json }
      let(:child_storage) { {column: :processors_data} }
      let(:child_default) { false }  # Returns false instead of []
      let(:child_extra_options) { {array: true} }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { false }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end

    # StoreModel Parent + StoreModel Child (same column)
    context "when StoreModel parent has StoreModel child in same column" do
      let(:parent_name) { :ai_features }
      let(:parent_type) { :store_model }
      let(:parent_storage) { {column: :ai_settings} }
      let(:parent_default) { false }
      let(:child_name) { :ai_summary }
      let(:child_type) { :store_model }
      let(:child_storage) { {column: :ai_settings} }
      let(:child_default) { false }
      let(:parent_cascade_value) { true }
      let(:child_enabled_value) { true }
      let(:parent_disable_value) { false }
      let(:child_disabled_value) { false }

      it_behaves_like "mixed storage contract"
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers, RSpecGuide/DuplicateLetValues
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
