# frozen_string_literal: true

require "test_helper"

class MonthlyPlanning::ReverseBudgetReportTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @cash = @family.categories.create!(name: "Cash root", classification: "expense", lucide_icon: "banknote")
    @card = @family.categories.create!(name: "Card root", classification: "expense", lucide_icon: "credit-card")
    @child_cash = @family.categories.create!(name: "Groceries", classification: "expense", parent: @cash, lucide_icon: "shopping-cart")
    @checking = @family.accounts.create!(name: "Checking", currency: @family.currency, balance: 10_000, accountable: Depository.new)
    @period = Period.custom(start_date: Date.current.beginning_of_month, end_date: Date.current.end_of_month)
  end

  test "excludes one-time transactions from totals" do
    create_transaction(account: @checking, amount: 100, category: @child_cash, date: Date.current)
    create_transaction(account: @checking, amount: 999, category: @child_cash, date: Date.current, kind: "one_time")

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: @cash.id
    ).call

    assert_equal 100, report.projected_total
  end

  test "uses gross expense bucket for category (refunds do not net into projected baselines)" do
    create_transaction(account: @checking, amount: 100, category: @child_cash, date: Date.current)
    create_transaction(account: @checking, amount: -30, category: @child_cash, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: @cash.id
    ).call

    assert_equal 100, report.projected_total
    assert_equal 100, report.projected_lines.first.total
  end

  test "buckets leaf spending under project root" do
    create_transaction(account: @checking, amount: 100, category: @child_cash, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: @cash.id
    ).call

    assert_equal 100, report.projected_total
    assert_equal 0, report.outside_total
    assert_equal 1, report.projected_lines.size
  end

  test "sends spending outside project tree to outside bucket" do
    other = @family.categories.create!(name: "Other", classification: "expense", lucide_icon: "circle")
    create_transaction(account: @checking, amount: 50, category: other, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: @cash.id,
      other_root_id: @card.id
    ).call

    assert_equal 0, report.projected_total
    assert_equal 50, report.outside_total
  end

  test "does not list second group child categories as outside" do
    child_card = @family.categories.create!(name: "Card line item", classification: "expense", parent: @card, lucide_icon: "circle")
    create_transaction(account: @checking, amount: 40, category: child_card, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: @cash.id,
      other_root_id: @card.id
    ).call

    assert_equal 0, report.projected_total
    assert_equal 0, report.outside_total
    assert_empty report.outside_lines
  end

  test "counts uncategorized spending in outside bucket without raising" do
    create_transaction(account: @checking, amount: 25, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: @cash.id
    ).call

    assert_equal 25, report.outside_total
    assert_equal 1, report.outside_lines.size
    assert_equal "Uncategorized", report.outside_lines.first.category_name
  end

  test "returns empty when project_root_id is blank" do
    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      project_root_id: nil
    ).call

    assert_equal 0, report.projected_total
    assert_equal 0, report.outside_total
  end
end
