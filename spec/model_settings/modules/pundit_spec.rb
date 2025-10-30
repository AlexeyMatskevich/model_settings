# frozen_string_literal: true

require "spec_helper"

RSpec.describe ModelSettings::Modules::Pundit do
  it_behaves_like "policy-based authorization module", :pundit, ModelSettings::Modules::Pundit
end
