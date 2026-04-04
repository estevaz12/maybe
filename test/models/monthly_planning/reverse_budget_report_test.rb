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

  test "buckets leaf spending under configured roots" do
    create_transaction(account: @checking, amount: 100, category: @child_cash, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      first_root_id: @cash.id,
      second_root_id: @card.id
    ).call

    assert_equal 100, report.first_root_total
    assert_equal 0, report.second_root_total
    assert_equal 0, report.outside_total
    assert_equal 1, report.first_root_lines.size
  end

  test "sends spending outside roots to outside bucket" do
    other = @family.categories.create!(name: "Other", classification: "expense", lucide_icon: "circle")
    create_transaction(account: @checking, amount: 50, category: other, date: Date.current)

    report = MonthlyPlanning::ReverseBudgetReport.new(
      family: @family,
      period: @period,
      first_root_id: @cash.id,
      second_root_id: @card.id
    ).call

    assert_equal 50, report.outside_total
  end
end
