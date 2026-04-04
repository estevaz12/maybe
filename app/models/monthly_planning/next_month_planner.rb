# frozen_string_literal: true

module MonthlyPlanning
  # Deterministic planning math: run-rate by calendar days, combined need, optional FX.
  class NextMonthPlanner
    Result = Data.define(
      :reference_month,
      :next_month,
      :days_in_reference_month,
      :days_in_next_month,
      :spent_run_rate_root,
      :spent_other_root,
      :inflation_multiplier,
      :projected_run_rate_spend,
      :combined_need_domestic,
      :simple_fx_rate,
      :simple_fx_amount_target_currency,
      :tiered_enabled,
      :tier_first_amount_usd,
      :tier_first_ars_per_usd,
      :tier_second_ars_per_usd,
      :tiered_breakdown
    )

    def initialize(
      reference_month:,
      next_month:,
      spent_run_rate_root:,
      spent_other_root:,
      inflation_percent:,
      simple_fx_rate: nil,
      tiered_enabled: false,
      tier_first_amount_usd: nil,
      tier_first_ars_per_usd: nil,
      tier_second_ars_per_usd: nil
    )
      @reference_month = reference_month.beginning_of_month
      @next_month = next_month.beginning_of_month
      @spent_run_rate_root = spent_run_rate_root.to_d
      @spent_other_root = spent_other_root.to_d
      @inflation_percent = inflation_percent.to_d
      @simple_fx_rate = simple_fx_rate&.to_d
      @tiered_enabled = tiered_enabled
      @tier_first_amount_usd = tier_first_amount_usd&.to_d
      @tier_first_ars_per_usd = tier_first_ars_per_usd&.to_d
      @tier_second_ars_per_usd = tier_second_ars_per_usd&.to_d
    end

    def call
      days_ref = @reference_month.end_of_month.day
      days_next = @next_month.end_of_month.day
      inflation_mult = 1 + (@inflation_percent / 100)

      daily = days_ref.positive? ? (@spent_run_rate_root / days_ref) : 0.to_d
      projected = daily * days_next * inflation_mult
      combined = projected + @spent_other_root

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
        days_in_reference_month: days_ref,
        days_in_next_month: days_next,
        spent_run_rate_root: @spent_run_rate_root,
        spent_other_root: @spent_other_root,
        inflation_multiplier: inflation_mult,
        projected_run_rate_spend: projected,
        combined_need_domestic: combined,
        simple_fx_rate: @simple_fx_rate,
        simple_fx_amount_target_currency: simple_target,
        tiered_enabled: @tiered_enabled,
        tier_first_amount_usd: @tier_first_amount_usd,
        tier_first_ars_per_usd: @tier_first_ars_per_usd,
        tier_second_ars_per_usd: @tier_second_ars_per_usd,
        tiered_breakdown: tiered
      )
    end

    private

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
