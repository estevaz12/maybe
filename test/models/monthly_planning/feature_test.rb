# frozen_string_literal: true

require "test_helper"

class MonthlyPlanning::FeatureTest < ActiveSupport::TestCase
  test "enabled when env is unset" do
    with_env_overrides("MONTHLY_PLANNING_ENABLED" => nil) do
      assert MonthlyPlanning::Feature.enabled?
    end
  end

  test "enabled when env is blank" do
    with_env_overrides("MONTHLY_PLANNING_ENABLED" => "") do
      assert MonthlyPlanning::Feature.enabled?
    end

    with_env_overrides("MONTHLY_PLANNING_ENABLED" => "   ") do
      assert MonthlyPlanning::Feature.enabled?
    end
  end

  test "enabled when env is true" do
    with_env_overrides("MONTHLY_PLANNING_ENABLED" => "true") do
      assert MonthlyPlanning::Feature.enabled?
    end
  end

  test "disabled when env is false" do
    with_env_overrides("MONTHLY_PLANNING_ENABLED" => "false") do
      assert_not MonthlyPlanning::Feature.enabled?
    end
  end
end
