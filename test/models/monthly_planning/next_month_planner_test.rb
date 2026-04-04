# frozen_string_literal: true

require "test_helper"

class MonthlyPlanning::NextMonthPlannerTest < ActiveSupport::TestCase
  test "projects run rate by days and combines with other root" do
    ref = Date.new(2026, 1, 1).beginning_of_month
    nxt = Date.new(2026, 2, 1).beginning_of_month
    # Jan has 31 days, Feb 2026 has 28 days
    spent_run = 3100 # 100/day in January
    spent_other = 500

    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: spent_run,
      spent_other_root: spent_other,
      inflation_percent: 0,
      simple_fx_rate: 1000
    ).call

    assert_equal 31, result.days_in_reference_month
    assert_equal 28, result.days_in_next_month
    assert_in_delta(100 * 28, result.projected_run_rate_spend.to_f, 0.01)
    assert_in_delta(100 * 28 + 500, result.combined_need_domestic.to_f, 0.01)
    assert_in_delta((100 * 28 + 500) / 1000.0, result.simple_fx_amount_target_currency.to_f, 0.0001)
  end

  test "applies inflation as percent" do
    ref = Date.new(2026, 3, 1)
    nxt = Date.new(2026, 4, 1)
    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: 3100,
      spent_other_root: 0,
      inflation_percent: 10,
      simple_fx_rate: 1
    ).call

    daily = 3100 / 31.0
    projected = daily * 30 * 1.10 # March has 31 days, April 30 days
    assert_in_delta projected, result.projected_run_rate_spend.to_f, 0.02
  end

  test "tiered split uses cap at first rate then second" do
    ref = Date.new(2026, 1, 1)
    nxt = Date.new(2026, 2, 1)
    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: 0,
      spent_other_root: 3_000_000,
      inflation_percent: 0,
      tiered_enabled: true,
      tier_first_amount_usd: 1500,
      tier_first_ars_per_usd: 1000,
      tier_second_ars_per_usd: 1200
    ).call

    b = result.tiered_breakdown
    assert_equal 1500, b[:first_usd].to_f
    assert_in_delta 1250, b[:second_usd].to_f, 0.01 # (3_000_000 - 1_500*1000) / 1200
  end
end
