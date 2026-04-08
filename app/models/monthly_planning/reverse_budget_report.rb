# frozen_string_literal: true

module MonthlyPlanning
  # Historical expense totals for the projected (pace) parent—leaf lines under that tree, plus an
  # "outside" bucket for spending under neither configured parent. The sibling "other" group’s
  # subtree is excluded from outside (that group is manual; we still don’t list it as uncategorized).
  class ReverseBudgetReport
    Line = Data.define(:category_id, :category_name, :total)
    Result = Data.define(
      :projected_total,
      :outside_total,
      :projected_lines,
      :outside_lines
    )

    def initialize(family:, period:, project_root_id:, other_root_id: nil)
      @family = family
      @period = period
      @project_root_id = project_root_id
      @other_root_id = other_root_id
    end

    def call
      return empty_result if @project_root_id.blank?

      project_root = @family.categories.find_by(id: @project_root_id)
      return empty_result if project_root.nil?

      other_root = @other_root_id.present? ? @family.categories.find_by(id: @other_root_id) : nil

      expense_totals = @family.income_statement.expense_totals(period: @period)
      leaf_map = build_leaf_total_map(expense_totals)

      projected_lines = []
      outside_lines = []

      category_ids = leaf_map.keys.compact
      categories_by_id = @family.categories.where(id: category_ids).index_by(&:id)

      category_ids.sort.each do |cat_id|
        cat = categories_by_id[cat_id]
        next unless cat && leaf_category?(cat)

        amount = leaf_map[cat_id]
        next if amount.nil? || amount.zero?

        line = Line.new(category_id: cat.id, category_name: cat.name, total: amount)
        if under_root?(cat, project_root)
          projected_lines << line
        elsif other_root && under_root?(cat, other_root)
          next
        else
          outside_lines << line
        end
      end

      append_uncategorized_outside_line!(outside_lines, leaf_map)

      Result.new(
        projected_total: sum_line_totals(projected_lines),
        outside_total: sum_line_totals(outside_lines),
        projected_lines: projected_lines.sort_by(&:category_name),
        outside_lines: outside_lines.sort_by(&:category_name)
      )
    end

    private

      def empty_result
        Result.new(
          projected_total: 0,
          outside_total: 0,
          projected_lines: [],
          outside_lines: []
        )
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

      def append_uncategorized_outside_line!(outside_lines, leaf_map)
        amount = leaf_map[nil]
        return if amount.nil? || amount.zero?

        uncategorized = Category.uncategorized
        outside_lines << Line.new(
          category_id: nil,
          category_name: uncategorized.name,
          total: amount
        )
      end

      def leaf_category?(category)
        return true if category.id.nil?

        category.subcategories.empty?
      end

      def under_root?(category, root)
        cat = category
        while cat
          return true if cat.id == root.id
          cat = cat.parent
        end
        false
      end

      def sum_line_totals(lines)
        lines.sum(BigDecimal("0"), &:total)
      end
  end
end
