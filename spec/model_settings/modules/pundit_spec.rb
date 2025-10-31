# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Modules::Pundit do
  it_behaves_like "policy-based authorization module", :pundit, described_class
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
