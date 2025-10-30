# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Modules::ActionPolicy do
  it_behaves_like "policy-based authorization module", :action_policy, ModelSettings::Modules::ActionPolicy
end
