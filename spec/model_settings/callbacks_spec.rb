# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
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

    # Tests for basic callback mechanism (Symbol, Proc, Array)
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

      it "can access instance variables in Proc callbacks" do
        instance.instance_variable_set(:@test_var, "test")
        setting.options[:after_enable] = -> { @test_var }  # rubocop:disable RSpec/InstanceVariable

        expect(instance.execute_setting_callbacks(setting, :enable, :after)).to be true
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
      before {} # rubocop:disable RSpec/EmptyHook
      # Edge case: testing fallback when no callback defined

      it "returns true" do
        expect(instance.execute_setting_callbacks(setting, :enable, :before)).to be true
      end
    end

    it "supports different action types (enable, disable, toggle, change)" do  # rubocop:disable RSpec/ExampleLength
      model_class.class_eval do
        def track_action
        end
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
        def track_callback
        end
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

    # Tests for validation callbacks
    context "with validation callbacks" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "ValidationCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :validation_log

          setting :premium,
            type: :column,
            default: false,
            before_validation: :log_before_validation,
            after_validation: :log_after_validation

          def log_before_validation
            self.validation_log ||= []
            self.validation_log << :before
          end

          def log_after_validation
            self.validation_log ||= []
            self.validation_log << :after
          end
        end
      end

      let(:instance) { model_class.new }
      let(:setting) { model_class.find_setting(:premium) }

      it "executes before_validation callback" do
        instance.execute_setting_callbacks(setting, :validation, :before)

        expect(instance.validation_log).to eq([:before])
      end

      it "executes after_validation callback" do
        instance.execute_setting_callbacks(setting, :validation, :after)

        expect(instance.validation_log).to eq([:after])
      end

      it "executes both callbacks in correct order" do
        instance.execute_setting_callbacks(setting, :validation, :before)
        instance.execute_setting_callbacks(setting, :validation, :after)

        expect(instance.validation_log).to eq([:before, :after])
      end
    end

    # Tests for destroy callbacks
    context "with destroy callbacks" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "DestroyCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :destroy_log

          setting :feature,
            type: :column,
            default: true,
            before_destroy: :log_before_destroy,
            after_destroy: :log_after_destroy

          def log_before_destroy
            self.destroy_log ||= []
            self.destroy_log << :before
          end

          def log_after_destroy
            self.destroy_log ||= []
            self.destroy_log << :after
          end
        end
      end

      let(:instance) { model_class.create! }
      let(:setting) { model_class.find_setting(:feature) }

      it "executes before_destroy callback" do
        instance.execute_setting_callbacks(setting, :destroy, :before)

        expect(instance.destroy_log).to eq([:before])
      end

      it "executes after_destroy callback" do
        instance.execute_setting_callbacks(setting, :destroy, :after)

        expect(instance.destroy_log).to eq([:after])
      end
    end

    # Tests for rollback callback
    context "with rollback callback" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "RollbackCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :rollback_fired

          setting :enabled,
            type: :column,
            default: false,
            after_change_rollback: :handle_rollback

          def handle_rollback
            self.rollback_fired = true
          end
        end
      end

      let(:instance) { model_class.new }
      let(:setting) { model_class.find_setting(:enabled) }

      it "executes after_change_rollback callback" do
        instance.execute_setting_callbacks(setting, :change_rollback, :after)

        expect(instance.rollback_fired).to be true
      end
    end

    # Tests for conditional execution (:if, :unless, :on, :prepend options)
    context "with :if condition" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "ConditionalCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :callback_executed, :condition_met

          setting :feature,
            type: :column,
            default: false,
            before_enable: :conditional_callback,
            if: :condition_met?

          def conditional_callback
            self.callback_executed = true
          end

          def condition_met?
            condition_met == true
          end
        end
      end

      let(:instance) { model_class.new }
      let(:setting) { model_class.find_setting(:feature) }

      context "when condition is true" do
        before { instance.condition_met = true }

        it "executes callback" do
          instance.execute_setting_callbacks(setting, :enable, :before)

          expect(instance.callback_executed).to be true
        end
      end

      context "when condition is false" do
        before { instance.condition_met = false }

        it "does not execute callback" do
          instance.execute_setting_callbacks(setting, :enable, :before)

          expect(instance.callback_executed).to be_nil
        end
      end
    end

    context "with :unless condition" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "UnlessCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :callback_executed, :skip_callback

          setting :notification,
            type: :column,
            default: true,
            after_disable: :notify_change,
            unless: :skip_callback?

          def notify_change
            self.callback_executed = true
          end

          def skip_callback?
            skip_callback == true
          end
        end
      end

      let(:instance) { model_class.new }
      let(:setting) { model_class.find_setting(:notification) }

      context "when condition is false" do
        before { instance.skip_callback = false }

        it "executes callback" do
          instance.execute_setting_callbacks(setting, :disable, :after)

          expect(instance.callback_executed).to be true
        end
      end

      context "when condition is true" do
        before { instance.skip_callback = true }

        it "does not execute callback" do
          instance.execute_setting_callbacks(setting, :disable, :after)

          expect(instance.callback_executed).to be_nil
        end
      end
    end

    context "with :on lifecycle phase" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "OnOptionCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :callback_log

          setting :audit_enabled,
            type: :column,
            default: false,
            before_enable: :log_create,
            on: :create

          def log_create
            self.callback_log ||= []
            self.callback_log << :create
          end
        end
      end

      let(:instance) { model_class.new }
      let(:setting) { model_class.find_setting(:audit_enabled) }

      it "executes callback when lifecycle phase matches" do
        instance.execute_setting_callbacks(setting, :enable, :before, phase: :create)

        expect(instance.callback_log).to eq([:create])
      end

      it "does not execute callback when lifecycle phase does not match" do
        instance.execute_setting_callbacks(setting, :enable, :before, phase: :update)

        expect(instance.callback_log).to be_nil
      end
    end

    context "with :prepend option for before_destroy" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "PrependCallbackModel"
          end

          include ModelSettings::DSL

          attr_accessor :callback_order

          setting :enabled,
            type: :column,
            default: true,
            before_destroy: [:cleanup_first, :cleanup_second],
            prepend: true

          def cleanup_first
            self.callback_order ||= []
            self.callback_order << :first
          end

          def cleanup_second
            self.callback_order ||= []
            self.callback_order << :second
          end
        end
      end

      let(:instance) { model_class.new }
      let(:setting) { model_class.find_setting(:enabled) }

      it "prepends callbacks to execution order" do
        instance.execute_setting_callbacks(setting, :destroy, :before)

        expect(instance.callback_order).to eq([:first, :second])
      end
    end
  end

  describe "#track_setting_change_for_commit" do
    let(:setting) { model_class.find_setting(:enabled) }

    it "adds setting to pending callbacks array and initializes if needed" do  # rubocop:disable RSpec/MultipleExpectations
      expect(instance.instance_variable_get(:@_pending_setting_callbacks)).to be_nil

      instance.track_setting_change_for_commit(setting)

      aggregate_failures do
        expect(instance.has_pending_setting_callbacks?).to be true
        expect(instance.instance_variable_get(:@_pending_setting_callbacks)).not_to be_nil
      end
    end

    it "does NOT add duplicate entries when adding same setting twice" do
      instance.track_setting_change_for_commit(setting)
      instance.track_setting_change_for_commit(setting)

      pending_count = instance.instance_variable_get(:@_pending_setting_callbacks)&.size
      expect(pending_count).to eq(1)
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
      before {} # rubocop:disable RSpec/EmptyHook
      # Edge case: testing default state (empty array)

      it "returns false" do
        expect(instance.has_pending_setting_callbacks?).to be false
      end
    end
  end

  describe "#run_pending_setting_callbacks" do
    let(:setting) { model_class.find_setting(:enabled) }

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

    context "when no pending callbacks" do
      before {} # rubocop:disable RSpec/EmptyHook
      # Edge case: testing no-op behavior (empty array)

      it "does nothing" do
        expect { instance.run_pending_setting_callbacks }.not_to raise_error
      end
    end
  end

  describe "#execute_around_callback" do
    let(:setting) { model_class.find_setting(:enabled) }

    context "when callback is Symbol" do
      before do
        model_class.class_eval do
          attr_accessor :call_order

          def around_callback
            self.call_order ||= []
            self.call_order << :before
            yield
            self.call_order << :after
          end
        end

        setting.options[:around_enable] = :around_callback
      end

      it "wraps the operation" do
        instance.call_order = []
        instance.execute_around_callback(setting, :enable) do
          instance.call_order << :operation
        end

        expect(instance.call_order).to eq([:before, :operation, :after])
      end

      it "executes operation when callback yields" do
        executed = false
        instance.execute_around_callback(setting, :enable) do
          executed = true
        end

        expect(executed).to be true
      end

      context "but when callback does NOT yield" do
        before do
          model_class.class_eval do
            def no_yield_callback
              # Deliberately don't yield
              self.call_order ||= []
              self.call_order << :callback_ran
            end
          end

          setting.options[:around_enable] = :no_yield_callback
        end

        it "does NOT execute the operation" do
          instance.call_order = []
          executed = false

          instance.execute_around_callback(setting, :enable) do
            executed = true
          end

          expect(executed).to be false
        end

        it "runs callback code" do
          instance.call_order = []

          instance.execute_around_callback(setting, :enable) {}

          expect(instance.call_order).to eq([:callback_ran])
        end
      end
    end

    context "when no around callback is defined" do
      before {} # rubocop:disable RSpec/EmptyHook
      # Edge case: testing direct execution fallback (no callback)

      it "executes the operation directly" do
        executed = false
        instance.execute_around_callback(setting, :enable) do
          executed = true
        end

        expect(executed).to be true
      end
    end

    context "when callback raises error" do
      before do
        model_class.class_eval do
          def error_callback
            raise StandardError, "callback error"
          end
        end

        setting.options[:around_enable] = :error_callback
      end

      it "returns false" do
        expect(instance.execute_around_callback(setting, :enable) {}).to be false
      end

      it "does NOT raise exception" do
        expect { instance.execute_around_callback(setting, :enable) {} }.not_to raise_error
      end
    end
  end

  describe "around callbacks in helper methods" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "AroundCallbackModel"
        end

        include ModelSettings::DSL

        attr_accessor :timing_log

        setting :feature, type: :column, default: false

        def log_timing
          self.timing_log ||= []
          self.timing_log << :start
          yield
          self.timing_log << :end
        end
      end
    end

    let(:instance) { model_class.create! }
    let(:setting) { model_class.find_setting(:feature) }

    it "logs timing around enable operation" do
      setting.options[:around_enable] = :log_timing
      instance.timing_log = []

      instance.feature_enable!

      expect(instance.timing_log).to eq([:start, :end])
    end

    it "enables the feature" do
      setting.options[:around_enable] = :log_timing

      instance.feature_enable!

      expect(instance.feature).to be true
    end

    it "logs timing around disable operation" do
      instance.feature = true
      instance.save!

      setting.options[:around_disable] = :log_timing
      instance.timing_log = []

      instance.feature_disable!

      expect(instance.timing_log).to eq([:start, :end])
    end

    it "disables the feature" do
      instance.feature = true
      instance.save!

      setting.options[:around_disable] = :log_timing

      instance.feature_disable!

      expect(instance.feature).to be false
    end

    context "when around callback aborts by not yielding" do
      before do
        model_class.class_eval do
          def abort_callback
            # Don't yield - abort operation
          end
        end

        setting.options[:around_enable] = :abort_callback
      end

      it "does NOT change the setting value" do
        instance.feature_enable!

        expect(instance.feature).to be false
      end
    end
  end

  describe "callback execution order" do
    let(:model_class) do
      Class.new(TestModel) do
        def self.name
          "ExecutionOrderModel"
        end

        include ModelSettings::DSL

        attr_accessor :execution_log

        setting :feature,
          type: :column,
          default: false,
          before_enable: :log_before_enable,
          around_enable: :log_around_enable,
          after_enable: :log_after_enable

        def log_before_enable
          self.execution_log ||= []
          self.execution_log << :before_enable
        end

        def log_around_enable
          self.execution_log ||= []
          self.execution_log << :around_enable_start
          yield
          self.execution_log << :around_enable_end
        end

        def log_after_enable
          self.execution_log ||= []
          self.execution_log << :after_enable
        end
      end
    end

    let(:instance) { model_class.create! }

    it "executes enable callbacks in correct order" do
      instance.execution_log = []

      instance.feature_enable!

      expect(instance.execution_log).to eq([
        :before_enable,
        :around_enable_start,
        :after_enable,
        :around_enable_end
      ])
    end

    it "includes value assignment between around callbacks" do
      instance.execution_log = []

      instance.feature_enable!

      aggregate_failures do
        expect(instance.feature).to be true
        expect(instance.execution_log.index(:around_enable_start)).to be < instance.execution_log.index(:around_enable_end)
      end
    end

    context "when around callback aborts by not yielding" do
      before do
        model_class.class_eval do
          def log_around_enable
            self.execution_log ||= []
            self.execution_log << :around_enable_start
            # Don't yield - abort operation
          end
        end
      end

      it "stops execution and does NOT change value" do
        instance.execution_log = []

        instance.feature_enable!

        aggregate_failures do
          expect(instance.feature).to be false
          expect(instance.execution_log).to eq([:before_enable, :around_enable_start])
        end
      end

      it "does NOT execute after_enable callback" do
        instance.execution_log = []

        instance.feature_enable!

        expect(instance.execution_log).not_to include(:after_enable)
      end
    end
  end

  # rubocop:disable RSpecGuide/MinimumBehavioralCoverage
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
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
