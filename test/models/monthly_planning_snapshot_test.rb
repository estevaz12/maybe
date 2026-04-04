# frozen_string_literal: true

require "test_helper"

class MonthlyPlanningSnapshotTest < ActiveSupport::TestCase
  test "reference month must be beginning of month" do
    snap = MonthlyPlanningSnapshot.new(
      family: families(:empty),
      reference_month: Date.new(2026, 1, 15),
      inputs: {},
      outputs: {}
    )
    assert_not snap.valid?
  end

  test "accepts first of month" do
    snap = MonthlyPlanningSnapshot.create!(
      family: families(:empty),
      reference_month: Date.new(2026, 1, 1),
      inputs: { "inflation_percent" => "5" },
      outputs: { "combined" => "100" }
    )
    assert snap.persisted?
  end
end
