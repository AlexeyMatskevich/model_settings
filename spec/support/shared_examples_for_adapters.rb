# frozen_string_literal: true

# Shared examples for adapter implementations
#
# These examples test the common behavior that all adapters must implement:
# - Helper methods (enable!, disable!, toggle!, enabled?, disabled?)
# - Dirty tracking (changed?, was, change)
# - Read/write operations
#
# Usage:
#   it_behaves_like "an adapter with helper methods"
#   it_behaves_like "an adapter with dirty tracking"
#   it_behaves_like "an adapter with read/write operations"

# rubocop:disable RSpecGuide/CharacteristicsAndContexts
RSpec.shared_examples "an adapter with helper methods" do
  # Expects:
  # - instance: model instance with setting defined
  # - setting_name: symbol name of the setting (e.g., :enabled)

  describe "helper methods" do
    describe "#setting_name_enable!" do
      context "when setting is disabled" do
        before { instance.update!("#{setting_name}": false) }

        it "sets the setting to true" do
          instance.public_send("#{setting_name}_enable!")
          expect(instance.public_send(setting_name)).to be true
        end

        it "marks the setting as changed" do
          instance.public_send("#{setting_name}_enable!")
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end

      context "when setting is already enabled" do
        before { instance.update!("#{setting_name}": true) }

        it "keeps the setting as true" do
          instance.public_send("#{setting_name}_enable!")
          expect(instance.public_send(setting_name)).to be true
        end

        it "does NOT mark as changed" do
          instance.public_send("#{setting_name}_enable!")
          expect(instance.public_send("#{setting_name}_changed?")).to be false
        end
      end
    end

    describe "#setting_name_disable!" do
      context "when setting is enabled" do
        before { instance.update!("#{setting_name}": true) }

        it "sets the setting to false" do
          instance.public_send("#{setting_name}_disable!")
          expect(instance.public_send(setting_name)).to be false
        end

        it "marks the setting as changed" do
          instance.public_send("#{setting_name}_disable!")
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end

      context "when setting is already disabled" do
        before { instance.update!("#{setting_name}": false) }

        it "keeps the setting as false" do
          instance.public_send("#{setting_name}_disable!")
          expect(instance.public_send(setting_name)).to be false
        end

        it "does NOT mark as changed" do
          instance.public_send("#{setting_name}_disable!")
          expect(instance.public_send("#{setting_name}_changed?")).to be false
        end
      end
    end

    describe "#setting_name_toggle!" do
      context "when setting is false" do
        before { instance.update!("#{setting_name}": false) }

        it "changes to true" do
          instance.public_send("#{setting_name}_toggle!")
          expect(instance.public_send(setting_name)).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!("#{setting_name}": true) }

        it "changes to false" do
          instance.public_send("#{setting_name}_toggle!")
          expect(instance.public_send(setting_name)).to be false
        end
      end
    end

    describe "#setting_name_enabled?" do
      context "when setting is true" do
        before { instance.update!("#{setting_name}": true) }

        it "returns true" do
          expect(instance.public_send("#{setting_name}_enabled?")).to be true
        end
      end

      context "when setting is false" do
        before { instance.update!("#{setting_name}": false) }

        it "returns false" do
          expect(instance.public_send("#{setting_name}_enabled?")).to be false
        end
      end
    end

    describe "#setting_name_disabled?" do
      context "when setting is false" do
        before { instance.update!("#{setting_name}": false) }

        it "returns true" do
          expect(instance.public_send("#{setting_name}_disabled?")).to be true
        end
      end

      context "when setting is true" do
        before { instance.update!("#{setting_name}": true) }

        it "returns false" do
          expect(instance.public_send("#{setting_name}_disabled?")).to be false
        end
      end
    end
  end
end
# rubocop:enable RSpecGuide/CharacteristicsAndContexts

# rubocop:disable RSpecGuide/CharacteristicsAndContexts
RSpec.shared_examples "an adapter with dirty tracking" do
  # Expects:
  # - instance: model instance with setting defined
  # - setting_name: symbol name of the setting
  # - adapter: adapter instance

  describe "dirty tracking" do
    describe "#changed?" do
      context "when value has changed" do
        before { instance.public_send("#{setting_name}=", true) }

        it "returns true" do
          expect(adapter.changed?(instance)).to be true
        end
      end

      context "when value has NOT changed" do
        let(:expected_result) { false }

        it "returns false" do
          expect(adapter.changed?(instance)).to be expected_result
        end
      end
    end

    describe "#was" do
      context "when value has changed" do
        before do
          instance.update!("#{setting_name}": false)
          instance.public_send("#{setting_name}=", true)
        end

        it "returns previous value" do
          expect(adapter.was(instance)).to be false
        end
      end

      context "when value has NOT changed" do
        let(:expected_value) { false }

        before { instance.update!("#{setting_name}": false) }

        it "returns current value" do
          expect(adapter.was(instance)).to be expected_value
        end
      end
    end

    describe "#change" do
      context "when value has changed" do
        before do
          instance.update!("#{setting_name}": false)
          instance.public_send("#{setting_name}=", true)
        end

        it "returns [old, new] array" do
          expect(adapter.change(instance)).to eq([false, true])
        end
      end

      context "when value has NOT changed" do
        let(:expected_change) { nil }

        before { instance.update!("#{setting_name}": false) }

        it "returns nil" do
          expect(adapter.change(instance)).to be expected_change
        end
      end
    end
  end
end
# rubocop:enable RSpecGuide/CharacteristicsAndContexts

# rubocop:disable RSpecGuide/CharacteristicsAndContexts
RSpec.shared_examples "an adapter with read/write operations" do
  # Expects:
  # - instance: model instance with setting defined
  # - setting_name: symbol name of the setting
  # - adapter: adapter instance

  describe "read/write operations" do
    describe "#read" do
      context "when value is true" do
        before { instance.update!("#{setting_name}": true) }

        it "reads true" do
          expect(adapter.read(instance)).to be true
        end
      end

      context "when value is false" do
        before { instance.update!("#{setting_name}": false) }

        it "reads false" do
          expect(adapter.read(instance)).to be false
        end
      end
    end

    describe "#write" do
      context "when writing true" do
        let(:new_value) { true }

        it "sets value to true" do
          adapter.write(instance, new_value)
          expect(instance.public_send(setting_name)).to be true
        end

        it "marks as changed" do
          adapter.write(instance, new_value)
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end

      context "when writing false" do
        let(:new_value) { false }

        before { instance.update!("#{setting_name}": true) }

        it "sets value to false" do
          adapter.write(instance, new_value)
          expect(instance.public_send(setting_name)).to be false
        end

        it "marks as changed" do
          adapter.write(instance, new_value)
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end
    end
  end
end
# rubocop:enable RSpecGuide/CharacteristicsAndContexts

# rubocop:disable RSpecGuide/CharacteristicsAndContexts
RSpec.shared_examples "an adapter with persistence" do
  # Expects:
  # - instance: model instance with setting defined
  # - setting_name: symbol name of the setting

  describe "persistence" do
    it "persists changes to database" do
      instance.public_send("#{setting_name}=", true)
      instance.save!
      expect(instance.reload.public_send(setting_name)).to be true
    end

    it "clears changes after save" do
      instance.public_send("#{setting_name}=", true)
      instance.save!
      expect(instance.public_send("#{setting_name}_changed?")).to be false
    end
  end
end
# rubocop:enable RSpecGuide/CharacteristicsAndContexts
