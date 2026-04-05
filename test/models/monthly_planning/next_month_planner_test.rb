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
      as_of_date: Date.new(2026, 1, 15),
      simple_fx_rate: 1000
    ).call

    assert_equal 31, result.days_in_reference_month
    assert_equal 28, result.days_in_next_month
    assert_in_delta(100 * 28, result.projected_run_rate_spend.to_f, 0.01)
    assert_in_delta(100 * 28 + 500, result.combined_need_domestic.to_f, 0.01)
    assert_in_delta((100 * 28 + 500) / 1000.0, result.simple_fx_amount_target_currency.to_f, 0.0001)
  end

  test "subtracts previous month surplus from run-rate before combining" do
    ref = Date.new(2026, 1, 1).beginning_of_month
    nxt = Date.new(2026, 2, 1).beginning_of_month
    spent_run = 3100
    spent_other = 500
    surplus = 800

    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: spent_run,
      spent_other_root: spent_other,
      inflation_percent: 0,
      previous_month_surplus: surplus,
      as_of_date: Date.new(2026, 1, 15),
      simple_fx_rate: 1000
    ).call

    gross = 100 * 28
    assert_in_delta gross, result.projected_run_rate_spend.to_f, 0.01
    assert_in_delta surplus, result.previous_month_surplus.to_f, 0.01
    assert_in_delta(gross - surplus, result.adjusted_projected_run_rate_spend.to_f, 0.01)
    assert_in_delta((gross - surplus) + spent_other, result.combined_need_domestic.to_f, 0.01)
  end

  test "surplus cannot drive adjusted run-rate below zero" do
    ref = Date.new(2026, 1, 1).beginning_of_month
    nxt = Date.new(2026, 2, 1).beginning_of_month
    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: 3100,
      spent_other_root: 100,
      inflation_percent: 0,
      previous_month_surplus: 100_000,
      as_of_date: Date.new(2026, 1, 15),
      simple_fx_rate: 1
    ).call

    assert_equal 0, result.adjusted_projected_run_rate_spend
    assert_in_delta 100, result.combined_need_domestic.to_f, 0.01
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
      as_of_date: Date.new(2026, 3, 20),
      simple_fx_rate: 1
    ).call

    daily = 3100 / 31.0
    projected = daily * 30 * 1.10 # March has 31 days, April 30 days
    assert_in_delta projected, result.projected_run_rate_spend.to_f, 0.02
  end

  test "uses remaining days in next month when as_of falls inside that month" do
    ref = Date.new(2026, 3, 1).beginning_of_month
    nxt = Date.new(2026, 4, 1).beginning_of_month
    spent_run = 3100 # 100/day over 31-day March
    as_of = Date.new(2026, 4, 10) # April has 30 days; 10 days elapsed → 20 remaining

    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: spent_run,
      spent_other_root: 0,
      inflation_percent: 0,
      as_of_date: as_of,
      simple_fx_rate: 1
    ).call

    assert_equal 30, result.days_in_next_month
    assert_equal 10, result.next_month_days_elapsed
    assert_equal 20, result.run_rate_days_next_month
    assert_in_delta 100 * 20, result.projected_run_rate_spend.to_f, 0.01
  end

  test "line breakdown matches aggregate when no overrides" do
    ref = Date.new(2026, 1, 1).beginning_of_month
    nxt = Date.new(2026, 2, 1).beginning_of_month
    lines = [
      { category_id: "a0000000-0000-0000-0000-000000000001", category_name: "A", baseline_spent: 1500 },
      { category_id: "a0000000-0000-0000-0000-000000000002", category_name: "B", baseline_spent: 1600 }
    ]

    agg = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: 3100,
      spent_other_root: 0,
      inflation_percent: 0,
      as_of_date: Date.new(2026, 1, 15),
      simple_fx_rate: 1
    ).call

    line = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: 3100,
      spent_other_root: 0,
      inflation_percent: 0,
      as_of_date: Date.new(2026, 1, 15),
      simple_fx_rate: 1,
      run_rate_lines: lines,
      reference_days_for_run_rate: 31,
      run_rate_line_inputs: {}
    ).call

    assert line.uses_line_breakdown
    assert_equal 2, line.run_rate_line_items.size
    assert_in_delta agg.projected_run_rate_spend.to_f, line.projected_run_rate_spend.to_f, 0.01
  end

  test "manual line uses fixed amount without pace or inflation" do
    ref = Date.new(2026, 1, 1).beginning_of_month
    nxt = Date.new(2026, 2, 1).beginning_of_month
    cid = "b0000000-0000-0000-0000-000000000001"
    lines = [
      { category_id: cid, category_name: "Groceries", baseline_spent: 3100 }
    ]

    result = MonthlyPlanning::NextMonthPlanner.new(
      reference_month: ref,
      next_month: nxt,
      spent_run_rate_root: 3100,
      spent_other_root: 0,
      inflation_percent: 50,
      as_of_date: Date.new(2026, 1, 15),
      simple_fx_rate: 1,
      run_rate_lines: lines,
      reference_days_for_run_rate: 31,
      run_rate_line_inputs: {
        cid => { "manual" => true, "manual_amount" => "400" }
      }
    ).call

    item = result.run_rate_line_items.find { |i| i.category_id == cid }
    assert item.use_manual
    assert_equal :manual, item.mode
    assert_in_delta 400, item.projected_amount.to_f, 0.01
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
      as_of_date: Date.new(2026, 1, 15),
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
