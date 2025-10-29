# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Adapters::Column, type: :model do
  # Create a fresh test model class for each test
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "TestModelWithSettings"
      end

      include ModelSettings::DSL

      setting :enabled, type: :column
      setting :premium_mode, type: :column, default: false
    end
  end

  describe "#setup!" do
    context "when setting is defined" do
      let(:instance) { model_class.new }

      it "creates enable! helper method" do
        expect(instance).to respond_to(:enabled_enable!)
      end

      it "creates disable! helper method" do
        expect(instance).to respond_to(:enabled_disable!)
      end

      it "creates toggle! helper method" do
        expect(instance).to respond_to(:enabled_toggle!)
      end

      it "creates enabled? helper method" do
        expect(instance).to respond_to(:enabled_enabled?)
      end

      it "creates disabled? helper method" do
        expect(instance).to respond_to(:enabled_disabled?)
      end
    end

    context "when setting is NOT defined" do
      let(:model_without_setting) do
        Class.new(ActiveRecord::Base) do
          self.table_name = "test_models"
        end
      end

      it "does NOT create helper methods" do
        instance = model_without_setting.new
        expect(instance).not_to respond_to(:enabled_enable!)
      end
    end
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "helper methods" do
    let(:instance) { model_class.create! }

    describe "#setting_name_enable!" do
      subject(:enable_action) { instance.enabled_enable! }

      context "when setting is disabled" do
        before { instance.update!(enabled: false) }

        it "sets the setting to true" do
          enable_action
          expect(instance.enabled).to be true
        end

        it "marks the setting as changed" do
          enable_action
          expect(instance.enabled_changed?).to be true
        end
      end

      context "when setting is already enabled" do
        before { instance.update!(enabled: true) }

        it "keeps the setting as true" do
          enable_action
          expect(instance.enabled).to be true
        end

        it "does NOT mark as changed" do
          enable_action
          expect(instance.enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_disable!" do
      subject(:disable_action) { instance.enabled_disable! }

      context "when setting is enabled" do
        before { instance.update!(enabled: true) }

        it "sets the setting to false" do
          disable_action
          expect(instance.enabled).to be false
        end

        it "marks the setting as changed" do
          disable_action
          expect(instance.enabled_changed?).to be true
        end
      end

      context "when setting is already disabled" do
        before { instance.update!(enabled: false) }

        it "keeps the setting as false" do
          disable_action
          expect(instance.enabled).to be false
        end

        it "does NOT mark as changed" do
          disable_action
          expect(instance.enabled_changed?).to be false
        end
      end
    end

    describe "#setting_name_toggle!" do
      subject(:toggle_action) { instance.enabled_toggle! }

      context "when setting is false" do
        before { instance.update!(enabled: false) }

        it "changes to true" do
          toggle_action
          expect(instance.enabled).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(enabled: true) }

        it "changes to false" do
          toggle_action
          expect(instance.enabled).to be false
        end
      end
    end

    describe "#setting_name_enabled?" do
      subject(:enabled_query) { instance.enabled_enabled? }

      context "when setting is true" do
        before { instance.update!(enabled: true) }

        it "returns true" do
          expect(enabled_query).to be true
        end
      end

      context "when setting is false" do
        before { instance.update!(enabled: false) }

        it "returns false" do
          expect(enabled_query).to be false
        end
      end
    end

    describe "#setting_name_disabled?" do
      subject(:disabled_query) { instance.enabled_disabled? }

      context "when setting is false" do
        before { instance.update!(enabled: false) }

        it "returns true" do
          expect(disabled_query).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!(enabled: true) }

        it "returns false" do
          expect(disabled_query).to be false
        end
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts

  describe "#read" do
    subject(:read_value) { adapter.read(instance) }

    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value is true" do
      let(:instance) { model_class.new(enabled: true) }

      it "reads true" do
        expect(read_value).to be true
      end
    end

    context "when value is false" do
      let(:instance) { model_class.new(enabled: false) }

      it "reads false" do
        expect(read_value).to be false
      end
    end
  end

  describe "#write" do
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when writing true" do
      subject(:write_action) { adapter.write(instance, true) }

      let(:instance) { model_class.new }

      it "sets value to true" do
        write_action
        expect(instance.enabled).to be true
      end

      it "marks as changed" do
        write_action
        expect(instance.enabled_changed?).to be true
      end
    end

    context "when writing false" do
      subject(:write_action) { adapter.write(instance, false) }

      let(:instance) { model_class.create!(enabled: true) }

      it "sets value to false" do
        write_action
        expect(instance.enabled).to be false
      end

      it "marks as changed" do
        write_action
        expect(instance.enabled_changed?).to be true
      end
    end
  end

  describe "#changed?" do
    let(:instance) { model_class.new }
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value has changed" do
      before { instance.enabled = true }

      it "returns true" do
        expect(adapter.changed?(instance)).to be true
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when value has NOT changed" do
      it "returns false" do
        expect(adapter.changed?(instance)).to be false
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup
  end

  describe "#was" do
    subject(:previous_value) { adapter.was(instance) }

    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value has changed" do
      let(:instance) { model_class.create!(enabled: false) }

      before { instance.enabled = true } # value changed

      it "returns previous value" do
        expect(previous_value).to be false
      end
    end

    context "when value has NOT changed" do
      let(:instance) { model_class.create!(enabled: true) } # create different instance to avoid the same expectation

      it "returns current value" do
        expect(previous_value).to be true
      end
    end
  end

  describe "#change" do
    subject(:change) { adapter.change(instance) }

    let(:instance) { model_class.create!(enabled: false) }
    let(:adapter) { described_class.new(model_class, model_class.find_setting(:enabled)) }

    context "when value has changed" do
      before { instance.enabled = true }

      it "returns [old, new] array" do
        expect(change).to eq([false, true])
      end
    end

    # rubocop:disable RSpecGuide/ContextSetup
    context "when value has NOT changed" do
      it "returns nil" do
        expect(change).to be_nil
      end
    end
    # rubocop:enable RSpecGuide/ContextSetup
  end

  # rubocop:disable RSpecGuide/CharacteristicsAndContexts
  describe "integration with ActiveRecord dirty tracking" do
    let(:instance) { model_class.create!(enabled: false, premium_mode: false) }

    describe "change tracking" do
      before { instance.enabled = true }

      it "marks setting as changed" do
        expect(instance.enabled_changed?).to be true
      end

      it "tracks previous value" do
        expect(instance.enabled_was).to be false
      end

      it "tracks change array" do
        expect(instance.enabled_change).to eq([false, true])
      end
    end

    describe "persistence" do
      before do
        instance.enabled = true
        instance.save!
      end

      it "persists changes to database" do
        reloaded = model_class.find(instance.id)
        expect(reloaded.enabled).to be true
      end

      it "clears changes after save" do
        expect(instance.enabled_changed?).to be false
      end
    end

    describe "multiple settings" do
      before do
        instance.enabled = true
        instance.premium_mode = true
      end

      it "tracks enabled setting as changed" do
        expect(instance.enabled_changed?).to be true
      end

      it "tracks premium_mode setting as changed" do
        expect(instance.premium_mode_changed?).to be true
      end

      it "includes both settings in changed list" do
        expect(instance.changed).to match_array(["enabled", "premium_mode"])
      end
    end
  end
  # rubocop:enable RSpecGuide/CharacteristicsAndContexts
end
