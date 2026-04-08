# frozen_string_literal: true

module MonthlyPlanning
  # Rehydrates stored snapshot JSON for the projection_results partial.
  class SnapshotPlannerView
    LineItem = Data.define(
      :category_id,
      :category_name,
      :baseline_spent,
      :inflation_percent,
      :use_manual,
      :manual_next_month_amount,
      :projected_amount,
      :mode
    )

    def initialize(snapshot)
      @snapshot = snapshot
      @out = (snapshot.outputs || {}).stringify_keys
    end

    def combined_need_domestic
      decimal(@out["combined_need_domestic"])
    end

    def uses_line_breakdown
      ActiveModel::Type::Boolean.new.cast(@out["uses_line_breakdown"])
    end

    def run_rate_line_items
      Array(@out["run_rate_line_items"]).filter_map do |raw|
        next if raw.blank?

        h = raw.stringify_keys
        mode_sym = h["mode"].to_s == "manual" ? :manual : :pace
        LineItem.new(
          category_id: h["category_id"].to_s,
          category_name: h["category_name"].to_s,
          baseline_spent: decimal(h["baseline_spent"]),
          inflation_percent: decimal(h["inflation_percent"]),
          use_manual: ActiveModel::Type::Boolean.new.cast(h["use_manual"]),
          manual_next_month_amount: decimal(h["manual_next_month_amount"]),
          projected_amount: decimal(h["projected_amount"]),
          mode: mode_sym
        )
      end
    end

    def simple_fx_amount_target_currency
      v = @out["simple_fx_amount_target_currency"]
      return if v.blank?

      decimal(v)
    end

    def tiered_breakdown
      tb = @out["tiered_breakdown"]
      return if tb.blank?

      tb = tb.stringify_keys
      {
        first_usd: decimal(tb["first_usd"]),
        second_usd: decimal(tb["second_usd"])
      }
    end

    def reference_month
      parse_month(@out["reference_month"]) || @snapshot.reference_month
    end

    def next_month
      parse_month(@out["next_month"]) || reference_month.next_month.beginning_of_month
    end

    def days_in_reference_month
      coalesce_int(@out["days_in_reference_month"]) { reference_month.end_of_month.day }
    end

    def days_in_next_month
      coalesce_int(@out["days_in_next_month"]) { next_month.end_of_month.day }
    end

    def run_rate_days_next_month
      coalesce_int(@out["run_rate_days_next_month"]) { days_in_next_month }
    end

    def pace_reference_days
      coalesce_int(@out["pace_reference_days"]) { days_in_reference_month }
    end

    def inflation_multiplier
      if @out["inflation_multiplier"].present?
        decimal(@out["inflation_multiplier"])
      else
        pct = decimal(@snapshot.inputs["inflation_percent"])
        1 + (pct / 100)
      end
    end

    def projected_run_rate_spend
      decimal(@out["projected_run_rate_spend"])
    end

    def previous_month_surplus
      if @out["previous_month_surplus"].present?
        decimal(@out["previous_month_surplus"])
      else
        decimal(@snapshot.inputs["previous_month_surplus"])
      end
    end

    def spent_other_root
      if @out["spent_other_root"].present?
        decimal(@out["spent_other_root"])
      else
        decimal(@snapshot.inputs["other_root_amount"])
      end
    end

    private

      def decimal(value)
        return 0.to_d if value.nil?

        BigDecimal(value.to_s)
      end

      def parse_month(value)
        return if value.blank?

        Date.parse(value.to_s).beginning_of_month
      end

      def coalesce_int(raw)
        return yield if raw.nil? || raw == ""

        raw.to_i
      end
  end
end
