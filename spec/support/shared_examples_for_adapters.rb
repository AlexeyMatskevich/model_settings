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

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.shared_examples "an adapter with helper methods" do
  # Expects:
  # - instance: model instance with setting defined
  # - setting_name: symbol name of the setting (e.g., :enabled)

  describe "helper methods" do
    describe "#setting_name_enable!" do
      context "when setting is disabled" do
        before { instance.update!("#{setting_name}": false) }

        it "enables setting and marks as changed", :aggregate_failures do
          instance.public_send("#{setting_name}_enable!")
          expect(instance.public_send(setting_name)).to be true
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end

      context "when setting is already enabled" do
        before { instance.update!("#{setting_name}": true) }

        it "keeps setting enabled and does NOT mark as changed", :aggregate_failures do
          instance.public_send("#{setting_name}_enable!")
          expect(instance.public_send(setting_name)).to be true
          expect(instance.public_send("#{setting_name}_changed?")).to be false
        end
      end
    end

    describe "#setting_name_disable!" do
      context "when setting is enabled" do
        before { instance.update!("#{setting_name}": true) }

        it "disables setting and marks as changed", :aggregate_failures do
          instance.public_send("#{setting_name}_disable!")
          expect(instance.public_send(setting_name)).to be false
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end

      context "when setting is already disabled" do
        before { instance.update!("#{setting_name}": false) }

        it "keeps setting disabled and does NOT mark as changed", :aggregate_failures do
          instance.public_send("#{setting_name}_disable!")
          expect(instance.public_send(setting_name)).to be false
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
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
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

      # rubocop:disable RSpecGuide/ContextSetup
      context "but when value has NOT changed" do  # No changes - testing default state
        it "returns false" do
          expect(adapter.changed?(instance)).to be false
        end
      end
      # rubocop:enable RSpecGuide/ContextSetup
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
        before { instance.update!("#{setting_name}": false) }

        it "returns current value" do
          expect(adapter.was(instance)).to be false
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
        before { instance.update!("#{setting_name}": false) }

        it "returns nil" do
          expect(adapter.change(instance)).to be_nil
        end
      end
    end
  end
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
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

        it "sets value to true and marks as changed", :aggregate_failures do
          adapter.write(instance, new_value)
          expect(instance.public_send(setting_name)).to be true
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end

      context "when writing false" do
        let(:new_value) { false }

        before { instance.update!("#{setting_name}": true) }

        it "sets value to false and marks as changed", :aggregate_failures do
          adapter.write(instance, new_value)
          expect(instance.public_send(setting_name)).to be false
          expect(instance.public_send("#{setting_name}_changed?")).to be true
        end
      end
    end
  end
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.shared_examples "an adapter with persistence" do
  # Expects:
  # - instance: model instance with setting defined
  # - setting_name: symbol name of the setting

  describe "persistence" do
    it "persists changes to database and clears change tracking", :aggregate_failures do
      instance.public_send("#{setting_name}=", true)
      instance.save!
      expect(instance.reload.public_send(setting_name)).to be true
      expect(instance.public_send("#{setting_name}_changed?")).to be false
    end
  end
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
