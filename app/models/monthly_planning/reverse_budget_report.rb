# frozen_string_literal: true

module MonthlyPlanning
  # Aggregates prior-month expense totals per planning root using leaf categories only
  # (avoids double-counting parent rollups from IncomeStatement).
  class ReverseBudgetReport
    Line = Data.define(:category_id, :category_name, :total)
    Result = Data.define(
      :first_root_total,
      :second_root_total,
      :outside_total,
      :first_root_lines,
      :second_root_lines,
      :outside_lines
    )

    def initialize(family:, period:, first_root_id:, second_root_id:)
      @family = family
      @period = period
      @first_root_id = first_root_id
      @second_root_id = second_root_id
    end

    def call
      return empty_result if @first_root_id.blank? || @second_root_id.blank?

      first_root = @family.categories.find_by(id: @first_root_id)
      second_root = @family.categories.find_by(id: @second_root_id)
      return empty_result if first_root.nil? || second_root.nil?

      expense_totals = @family.income_statement.expense_totals(period: @period)

      first_lines = []
      second_lines = []
      outside_lines = []

      leaf_expense_category_totals(expense_totals).each do |ct|
        bucket = bucket_for(ct.category, first_root:, second_root:)
        line = Line.new(category_id: ct.category.id, category_name: ct.category.name, total: ct.total)
        case bucket
        when :first_root then first_lines << line
        when :second_root then second_lines << line
        else outside_lines << line
        end
      end

      Result.new(
        first_root_total: first_lines.sum(&:total),
        second_root_total: second_lines.sum(&:total),
        outside_total: outside_lines.sum(&:total),
        first_root_lines: first_lines.sort_by(&:category_name),
        second_root_lines: second_lines.sort_by(&:category_name),
        outside_lines: outside_lines.sort_by(&:category_name)
      )
    end

    private

      def empty_result
        Result.new(
          first_root_total: 0,
          second_root_total: 0,
          outside_total: 0,
          first_root_lines: [],
          second_root_lines: [],
          outside_lines: []
        )
      end

      def leaf_expense_category_totals(expense_totals)
        expense_totals.category_totals.select do |ct|
          next false if ct.total.zero?

          cat = ct.category
          leaf_category?(cat)
        end
      end

      def leaf_category?(category)
        return true if category.id.nil?

        category.subcategories.empty?
      end

      def bucket_for(category, first_root:, second_root:)
        cat = category
        while cat
          return :first_root if cat.id == first_root.id
          return :second_root if cat.id == second_root.id
          cat = cat.parent
        end
        :outside
      end
  end
end
