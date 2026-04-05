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

    def initialize(family:, period:, first_root_id:, second_root_id:, second_period: nil)
      @family = family
      @period = period
      @second_period = second_period || period
      @first_root_id = first_root_id
      @second_root_id = second_root_id
    end

    def call
      return empty_result if @first_root_id.blank? || @second_root_id.blank?

      first_root = @family.categories.find_by(id: @first_root_id)
      second_root = @family.categories.find_by(id: @second_root_id)
      return empty_result if first_root.nil? || second_root.nil?

      expense_totals_first = @family.income_statement.expense_totals(period: @period)
      expense_totals_second = if same_period?(@period, @second_period)
        expense_totals_first
      else
        @family.income_statement.expense_totals(period: @second_period)
      end

      first_map = build_leaf_total_map(expense_totals_first)
      second_map = build_leaf_total_map(expense_totals_second)

      first_lines = []
      second_lines = []
      outside_lines = []

      category_ids = (first_map.keys | second_map.keys)
      categories_by_id = @family.categories.where(id: category_ids).index_by(&:id)

      category_ids.sort.each do |cat_id|
        cat = categories_by_id[cat_id]
        next unless cat && leaf_category?(cat)

        bucket = bucket_for(cat, first_root:, second_root:)
        amount = case bucket
        when :second_root then second_map[cat_id].to_i
        else first_map[cat_id].to_i
        end
        next if amount.zero?

        line = Line.new(category_id: cat.id, category_name: cat.name, total: amount)
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

      def same_period?(a, b)
        a.start_date == b.start_date && a.end_date == b.end_date
      end

      def build_leaf_total_map(expense_totals)
        leaf_expense_category_totals(expense_totals).each_with_object({}) do |ct, h|
          h[ct.category.id] = ct.total
        end
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
