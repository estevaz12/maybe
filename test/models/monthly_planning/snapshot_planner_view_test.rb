# frozen_string_literal: true

require "test_helper"

class MonthlyPlanning::SnapshotPlannerViewTest < ActiveSupport::TestCase
  test "rehydrates outputs for projection partial" do
    family = families(:empty)
    snap = MonthlyPlanningSnapshot.create!(
      family: family,
      reference_month: Date.new(2026, 2, 1),
      inputs: {
        "inflation_percent" => "5",
        "previous_month_surplus" => "10",
        "other_root_amount" => "200"
      },
      outputs: {
        "combined_need_domestic" => "1500.5",
        "uses_line_breakdown" => false,
        "run_rate_line_items" => [],
        "reference_month" => "2026-02-01",
        "next_month" => "2026-03-01",
        "days_in_reference_month" => "28",
        "days_in_next_month" => "31",
        "run_rate_days_next_month" => "31",
        "pace_reference_days" => "28",
        "inflation_multiplier" => "1.05",
        "projected_run_rate_spend" => "1310.5",
        "previous_month_surplus" => "10",
        "spent_other_root" => "200"
      }
    )

    view = MonthlyPlanning::SnapshotPlannerView.new(snap)

    assert_equal BigDecimal("1500.5"), view.combined_need_domestic
    assert_equal Date.new(2026, 2, 1), view.reference_month
    assert_equal Date.new(2026, 3, 1), view.next_month
    assert_equal BigDecimal("1.05"), view.inflation_multiplier
    assert_not view.uses_line_breakdown
    assert_empty view.run_rate_line_items
  end

  test "falls back when optional output keys missing" do
    family = families(:empty)
    snap = MonthlyPlanningSnapshot.create!(
      family: family,
      reference_month: Date.new(2026, 4, 1),
      inputs: { "inflation_percent" => "10", "previous_month_surplus" => "0", "other_root_amount" => "50" },
      outputs: {
        "combined_need_domestic" => "100",
        "uses_line_breakdown" => false,
        "run_rate_line_items" => []
      }
    )

    view = MonthlyPlanning::SnapshotPlannerView.new(snap)

    assert_equal 30, view.days_in_reference_month
    assert_equal BigDecimal("1.1"), view.inflation_multiplier
    assert_equal BigDecimal("50"), view.spent_other_root
  end
end
