# frozen_string_literal: true

module MonthlyPlanning
  # Deterministic planning math: run-rate by calendar days (per subcategory or aggregate),
  # combined need, optional FX.
  class NextMonthPlanner
    RunRateLineItem = Data.define(
      :category_id,
      :category_name,
      :baseline_spent,
      :inflation_percent,
      :use_manual,
      :manual_next_month_amount,
      :projected_amount,
      :mode
    )

    Result = Data.define(
      :reference_month,
      :next_month,
      :as_of_date,
      :days_in_reference_month,
      :days_in_next_month,
      :next_month_days_elapsed,
      :run_rate_days_next_month,
      :spent_run_rate_root,
      :spent_other_root,
      :inflation_multiplier,
      :default_inflation_percent,
      :previous_month_surplus,
      :projected_run_rate_spend,
      :adjusted_projected_run_rate_spend,
      :combined_need_domestic,
      :simple_fx_rate,
      :simple_fx_amount_target_currency,
      :tiered_enabled,
      :tier_first_amount_usd,
      :tier_first_ars_per_usd,
      :tier_second_ars_per_usd,
      :tiered_breakdown,
      :uses_line_breakdown,
      :run_rate_line_items,
      :pace_reference_days
    )

    def initialize(
      reference_month:,
      next_month:,
      spent_run_rate_root:,
      spent_other_root:,
      inflation_percent:,
      previous_month_surplus: 0,
      as_of_date: Date.current,
      simple_fx_rate: nil,
      tiered_enabled: false,
      tier_first_amount_usd: nil,
      tier_first_ars_per_usd: nil,
      tier_second_ars_per_usd: nil,
      run_rate_lines: nil,
      reference_days_for_run_rate: nil,
      run_rate_line_inputs: {}
    )
      @reference_month = reference_month.beginning_of_month
      @next_month = next_month.beginning_of_month
      @spent_run_rate_root = spent_run_rate_root.to_d
      @spent_other_root = spent_other_root.to_d
      @inflation_percent = inflation_percent.to_d
      @previous_month_surplus = previous_month_surplus.to_d
      @as_of_date = as_of_date.to_date
      @simple_fx_rate = simple_fx_rate&.to_d
      @tiered_enabled = tiered_enabled
      @tier_first_amount_usd = tier_first_amount_usd&.to_d
      @tier_first_ars_per_usd = tier_first_ars_per_usd&.to_d
      @tier_second_ars_per_usd = tier_second_ars_per_usd&.to_d
      @run_rate_lines = run_rate_lines
      @reference_days_for_run_rate = reference_days_for_run_rate&.to_i
      @run_rate_line_inputs = normalize_run_rate_line_inputs(run_rate_line_inputs)
    end

    def call
      days_ref_calendar = @reference_month.end_of_month.day
      calendar_days_next = @next_month.end_of_month.day
      run_days_next, days_elapsed_next = next_month_run_rate_and_elapsed(calendar_days_next)
      default_inflation_mult = 1 + (@inflation_percent / 100)

      line_items, projected_run, uses_lines = if use_line_breakdown?
        build_from_run_rate_lines(
          days_ref: @reference_days_for_run_rate,
          run_days: run_days_next,
          default_inflation_mult: default_inflation_mult
        )
      else
        [ [], build_aggregate_projected_run_rate(days_ref_calendar, run_days_next, default_inflation_mult), false ]
      end

      pace_ref_days = uses_lines ? @reference_days_for_run_rate : days_ref_calendar

      adjusted_run = projected_run - @previous_month_surplus
      adjusted_run = 0.to_d if adjusted_run.negative?
      combined = adjusted_run + @spent_other_root

      simple_target = if @simple_fx_rate.present? && !@simple_fx_rate.zero?
        combined / @simple_fx_rate
      end

      tiered = nil
      if @tiered_enabled && tiered_rates_complete?
        tiered = tiered_usd_split(combined, @tier_first_amount_usd, @tier_first_ars_per_usd, @tier_second_ars_per_usd)
      end

      Result.new(
        reference_month: @reference_month,
        next_month: @next_month,
        as_of_date: @as_of_date,
        days_in_reference_month: days_ref_calendar,
        days_in_next_month: calendar_days_next,
        next_month_days_elapsed: days_elapsed_next,
        run_rate_days_next_month: run_days_next,
        spent_run_rate_root: @spent_run_rate_root,
        spent_other_root: @spent_other_root,
        inflation_multiplier: default_inflation_mult,
        default_inflation_percent: @inflation_percent,
        previous_month_surplus: @previous_month_surplus,
        projected_run_rate_spend: projected_run,
        adjusted_projected_run_rate_spend: adjusted_run,
        combined_need_domestic: combined,
        simple_fx_rate: @simple_fx_rate,
        simple_fx_amount_target_currency: simple_target,
        tiered_enabled: @tiered_enabled,
        tier_first_amount_usd: @tier_first_amount_usd,
        tier_first_ars_per_usd: @tier_first_ars_per_usd,
        tier_second_ars_per_usd: @tier_second_ars_per_usd,
        tiered_breakdown: tiered,
        uses_line_breakdown: uses_lines,
        run_rate_line_items: line_items,
        pace_reference_days: pace_ref_days
      )
    end

    private

      def use_line_breakdown?
        @run_rate_lines.present? && @reference_days_for_run_rate.present? && @reference_days_for_run_rate.positive?
      end

      def normalize_run_rate_line_inputs(raw)
        return {} if raw.blank?

        hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
        hash.each_with_object({}) do |(cat_id, attrs), out|
          next unless cat_id.to_s.match?(/\A[0-9a-f-]{36}\z/i)

          a = attrs.respond_to?(:to_unsafe_h) ? attrs.to_unsafe_h : attrs
          a = a.stringify_keys
          out[cat_id.to_s] = {
            "manual" => ActiveModel::Type::Boolean.new.cast(a["manual"]),
            "manual_amount" => a["manual_amount"].presence
          }
        end
      end

      def build_from_run_rate_lines(days_ref:, run_days:, default_inflation_mult:)
        items = []
        projected_sum = 0.to_d

        @run_rate_lines.each do |line|
          cid = line[:category_id].to_s
          name = line[:category_name].to_s
          baseline = line[:baseline_spent].to_d
          input = @run_rate_line_inputs[cid] || {}

          use_manual = input["manual"]
          manual_amt = input["manual_amount"].to_s.presence&.to_d || 0.to_d

          if use_manual
            proj = manual_amt
            mode = :manual
            line_inflation_pct = 0.to_d
          else
            daily = days_ref.positive? ? (baseline / days_ref) : 0.to_d
            proj = daily * run_days * default_inflation_mult
            mode = :pace
            line_inflation_pct = @inflation_percent
          end

          projected_sum += proj

          items << RunRateLineItem.new(
            category_id: cid,
            category_name: name,
            baseline_spent: baseline,
            inflation_percent: line_inflation_pct,
            use_manual: use_manual,
            manual_next_month_amount: use_manual ? manual_amt : 0.to_d,
            projected_amount: proj,
            mode: mode
          )
        end

        [ items.sort_by(&:category_name), projected_sum, true ]
      end

      def build_aggregate_projected_run_rate(days_ref, run_days, inflation_mult)
        return 0.to_d if days_ref.zero?

        daily = @spent_run_rate_root / days_ref
        daily * run_days * inflation_mult
      end

      # When "today" falls inside the projected month, only the remaining calendar days get
      # run-rate need; days already elapsed in that month reduce the multiplier. When viewing
      # past months (as_of after month end), use the full calendar month for replay.
      def next_month_run_rate_and_elapsed(calendar_days)
        next_start = @next_month.beginning_of_month
        next_end = @next_month.end_of_month
        as_of = @as_of_date

        if as_of < next_start
          [ calendar_days, 0 ]
        elsif as_of > next_end
          [ calendar_days, calendar_days ]
        else
          elapsed = (as_of - next_start).to_i + 1
          run_days = [ calendar_days - elapsed, 0 ].max
          [ run_days, elapsed ]
        end
      end

      def tiered_rates_complete?
        @tier_first_amount_usd && @tier_first_ars_per_usd && @tier_second_ars_per_usd &&
          !@tier_first_ars_per_usd.zero? && !@tier_second_ars_per_usd.zero?
      end

      # total_ars: domestic amount to convert; cap_usd: max USD at first rate; rates are ARS per 1 USD.
      def tiered_usd_split(total_ars, cap_usd, rate_a, rate_b)
        usd_if_all_first = total_ars / rate_a
        if usd_if_all_first <= cap_usd
          {
            first_usd: usd_if_all_first,
            second_usd: 0.to_d,
            ars_at_first_rate: total_ars,
            ars_at_second_rate: 0.to_d
          }
        else
          ars_first = cap_usd * rate_a
          ars_remaining = total_ars - ars_first
          second_usd = ars_remaining / rate_b
          {
            first_usd: cap_usd,
            second_usd: second_usd,
            ars_at_first_rate: ars_first,
            ars_at_second_rate: ars_remaining
          }
        end
      end
  end
end
