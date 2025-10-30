# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Callbacks do
  let(:model_class) do
    Class.new(TestModel) do
      def self.name
        "CallbacksTestModel"
      end

      include ModelSettings::DSL

      setting :enabled, type: :column, default: false
      setting :premium_mode, type: :column, default: false
    end
  end

  let(:instance) { model_class.create! }

  describe "#execute_setting_callbacks" do
    let(:setting) { model_class.find_setting(:enabled) }

    context "when callback is Symbol" do
      before do
        model_class.class_eval do
          attr_accessor :callback_executed

          def my_callback
            self.callback_executed = true
          end
        end

        setting.options[:before_enable] = :my_callback
      end

      it "calls instance method and returns true" do
        result = instance.execute_setting_callbacks(setting, :enable, :before)

        aggregate_failures do
          expect(instance.callback_executed).to be true
          expect(result).to be true
        end
      end
    end

    context "when callback is Proc" do
      before do
        model_class.class_eval do
          attr_accessor :proc_value
        end

        setting.options[:after_enable] = -> { self.proc_value = "executed" }
      end

      it "executes proc in instance context and returns true" do
        result = instance.execute_setting_callbacks(setting, :enable, :after)

        aggregate_failures do
          expect(instance.proc_value).to eq("executed")
          expect(result).to be true
        end
      end

      context "but with access to instance variables" do
        it "can access instance variables" do
          instance.instance_variable_set(:@test_var, "test")
          setting.options[:after_enable] = -> { @test_var }

          expect(instance.execute_setting_callbacks(setting, :enable, :after)).to be true
        end
      end
    end

    context "when callback is Array" do
      before do
        model_class.class_eval do
          attr_accessor :callback_log

          def callback_one
            self.callback_log ||= []
            self.callback_log << :one
          end

          def callback_two
            self.callback_log ||= []
            self.callback_log << :two
          end
        end

        setting.options[:before_disable] = [:callback_one, :callback_two]
      end

      it "executes all callbacks in order and returns true" do
        result = instance.execute_setting_callbacks(setting, :disable, :before)

        aggregate_failures do
          expect(instance.callback_log).to eq([:one, :two])
          expect(result).to be true
        end
      end
    end

    context "when callback is nil" do
      it "returns true" do
        expect(instance.execute_setting_callbacks(setting, :enable, :before)).to be true
      end
    end

    it "supports different action types (enable, disable, toggle, change)" do
      model_class.class_eval do
        def track_action; end
      end

      aggregate_failures "all action types" do
        setting.options[:before_enable] = :track_action
        expect(instance.execute_setting_callbacks(setting, :enable, :before)).to be true

        setting.options[:after_disable] = :track_action
        expect(instance.execute_setting_callbacks(setting, :disable, :after)).to be true

        setting.options[:before_toggle] = :track_action
        expect(instance.execute_setting_callbacks(setting, :toggle, :before)).to be true

        setting.options[:after_change] = :track_action
        expect(instance.execute_setting_callbacks(setting, :change, :after)).to be true
      end
    end

    it "supports different timing types (before, after)" do
      model_class.class_eval do
        def track_callback; end
      end

      aggregate_failures "all timing types" do
        setting.options[:before_enable] = :track_callback
        expect(instance.execute_setting_callbacks(setting, :enable, :before)).to be true

        setting.options[:after_enable] = :track_callback
        expect(instance.execute_setting_callbacks(setting, :enable, :after)).to be true
      end
    end

    context "but when callback raises error" do
      before do
        model_class.class_eval do
          def failing_callback
            raise StandardError, "callback failed"
          end
        end

        setting.options[:before_enable] = :failing_callback
      end

      it "returns false and does NOT raise exception" do
        aggregate_failures do
          expect(instance.execute_setting_callbacks(setting, :enable, :before)).to be false
          expect { instance.execute_setting_callbacks(setting, :enable, :before) }.not_to raise_error
        end
      end
    end
  end

  describe "#track_setting_change_for_commit" do
    let(:setting) { model_class.find_setting(:enabled) }

    it "adds setting to pending callbacks array and initializes if needed" do
      expect(instance.instance_variable_get(:@_pending_setting_callbacks)).to be_nil

      instance.track_setting_change_for_commit(setting)

      aggregate_failures do
        expect(instance.has_pending_setting_callbacks?).to be true
        expect(instance.instance_variable_get(:@_pending_setting_callbacks)).not_to be_nil
      end
    end

    context "but when adding duplicate settings" do
      it "does NOT add duplicate entries" do
        instance.track_setting_change_for_commit(setting)
        instance.track_setting_change_for_commit(setting)

        pending_count = instance.instance_variable_get(:@_pending_setting_callbacks)&.size
        expect(pending_count).to eq(1)
      end
    end
  end

  describe "#has_pending_setting_callbacks?" do
    let(:setting) { model_class.find_setting(:enabled) }

    context "when pending callbacks exist" do
      before { instance.track_setting_change_for_commit(setting) }

      it "returns true" do
        expect(instance.has_pending_setting_callbacks?).to be true
      end
    end

    context "when no pending callbacks" do
      it "returns false" do
        expect(instance.has_pending_setting_callbacks?).to be false
      end
    end
  end

  describe "#run_pending_setting_callbacks" do
    let(:setting) { model_class.find_setting(:enabled) }

    context "when pending callbacks exist" do
      context "with after_change_commit as Symbol" do
        before do
          model_class.class_eval do
            attr_accessor :commit_callback_executed

            def my_commit_callback
              self.commit_callback_executed = true
            end
          end

          setting.options[:after_change_commit] = :my_commit_callback
          instance.track_setting_change_for_commit(setting)
        end

        it "calls instance method and clears pending callbacks" do
          instance.run_pending_setting_callbacks

          aggregate_failures do
            expect(instance.commit_callback_executed).to be true
            expect(instance.has_pending_setting_callbacks?).to be false
          end
        end
      end

      context "with after_change_commit as Proc" do
        before do
          model_class.class_eval do
            attr_accessor :proc_result
          end

          setting.options[:after_change_commit] = -> { self.proc_result = "committed" }
          instance.track_setting_change_for_commit(setting)
        end

        it "executes proc and clears pending callbacks" do
          instance.run_pending_setting_callbacks

          aggregate_failures do
            expect(instance.proc_result).to eq("committed")
            expect(instance.has_pending_setting_callbacks?).to be false
          end
        end
      end

      context "with after_change_commit as Array" do
        before do
          model_class.class_eval do
            attr_accessor :callback_log

            def commit_one
              self.callback_log ||= []
              self.callback_log << :commit_one
            end

            def commit_two
              self.callback_log ||= []
              self.callback_log << :commit_two
            end
          end

          setting.options[:after_change_commit] = [:commit_one, :commit_two]
          instance.track_setting_change_for_commit(setting)
        end

        it "calls all callbacks in order and clears pending callbacks" do
          instance.run_pending_setting_callbacks

          aggregate_failures do
            expect(instance.callback_log).to eq([:commit_one, :commit_two])
            expect(instance.has_pending_setting_callbacks?).to be false
          end
        end
      end

      context "but when callback raises error" do
        before do
          model_class.class_eval do
            def failing_commit_callback
              raise StandardError, "commit callback failed"
            end
          end

          setting.options[:after_change_commit] = :failing_commit_callback
          instance.track_setting_change_for_commit(setting)
        end

        it "does NOT raise exception and still clears pending callbacks" do
          aggregate_failures do
            expect { instance.run_pending_setting_callbacks }.not_to raise_error
            expect(instance.has_pending_setting_callbacks?).to be false
          end
        end
      end
    end

    context "when no pending callbacks" do
      it "does nothing" do
        expect { instance.run_pending_setting_callbacks }.not_to raise_error
      end
    end
  end

  describe "integration with ActiveRecord" do
    context "when after_commit hook fires" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "AfterCommitModel"
          end

          include ModelSettings::DSL

          attr_accessor :commit_fired

          setting :enabled,
            type: :column,
            default: false,
            after_change_commit: :on_commit

          def on_commit
            self.commit_fired = true
          end
        end
      end

      let(:instance) { model_class.create! }
      let(:setting) { model_class.find_setting(:enabled) }

      # Note: after_commit hooks don't fire in transactional fixtures (rollback)
      # This is expected Rails behavior - after_commit only fires on real commits
      it "runs pending callbacks automatically after save", skip: "after_commit doesn't fire in transactional fixtures" do
        instance.track_setting_change_for_commit(setting)
        instance.save!

        expect(instance.commit_fired).to be true
      end

      it "only runs when has_pending_setting_callbacks? is true", skip: "after_commit doesn't fire in transactional fixtures" do
        # Don't track any changes
        instance.commit_fired = false
        instance.save!

        # Callback should not fire
        expect(instance.commit_fired).to be_falsy
      end
    end
  end
end
