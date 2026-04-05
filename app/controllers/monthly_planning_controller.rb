# frozen_string_literal: true

class MonthlyPlanningController < ApplicationController
  before_action :ensure_feature_enabled
  before_action :set_reference_month, except: %i[show_snapshot]
  before_action :load_planning_context, only: %i[show create_snapshot preview]
  before_action :set_snapshot, only: %i[show_snapshot]

  def show; end

  def preview
    unless @planner
      return render json: { error: "no_projection" }, status: :unprocessable_entity
    end

    render json: {
      summary_html: render_to_string(
        partial: "monthly_planning/projection_results",
        locals: { planner: @planner, planning_setting: @setting },
        layout: false,
        formats: [ :html ]
      )
    }
  end

  def show_snapshot; end

  def update_settings
    @setting = Current.family.family_monthly_planning_setting || FamilyMonthlyPlanningSetting.new(family: Current.family)
    @setting.assign_attributes(settings_params)
    if @setting.save
      redirect_to monthly_planning_path(Budget.date_to_param(@reference_month)), notice: "Monthly planning settings saved."
    else
      populate_monthly_planning_assigns
      flash.now[:alert] = @setting.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def create_snapshot
    snap = Current.family.monthly_planning_snapshots.build(
      reference_month: @reference_month.beginning_of_month,
      inputs: snapshot_inputs_from_request,
      outputs: snapshot_outputs_from_planner
    )
    if snap.save
      redirect_to monthly_planning_path(Budget.date_to_param(@reference_month)), notice: "Snapshot saved."
    else
      flash.now[:alert] = snap.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

    def set_snapshot
      @snapshot = Current.family.monthly_planning_snapshots.find(params[:id])
    end

    def ensure_feature_enabled
      return if ENV.fetch("MONTHLY_PLANNING_ENABLED", "true") == "true"

      head :not_found
    end

    def set_reference_month
      param = params[:month_year].presence || Budget.date_to_param(Date.current.prev_month)
      @reference_month = Budget.param_to_date(param)
    rescue ArgumentError
      raise ActiveRecord::RecordNotFound
    end

    def load_planning_context
      @setting ||= Current.family.family_monthly_planning_setting || Current.family.build_family_monthly_planning_setting
      populate_monthly_planning_assigns
    end

    def populate_monthly_planning_assigns
      @period = Period.custom(start_date: @reference_month.beginning_of_month, end_date: @reference_month.end_of_month)
      @second_period_for_report = resolved_second_root_period
      @second_period_start_value = params.dig(:planning, :second_period_start).presence || @setting.second_root_period_start&.strftime("%Y-%m-%d")
      @second_period_end_value = params.dig(:planning, :second_period_end).presence || @setting.second_root_period_end&.strftime("%Y-%m-%d")
      @report = MonthlyPlanning::ReverseBudgetReport.new(
        family: Current.family,
        period: @period,
        first_root_id: @setting.first_root_category_id,
        second_root_id: @setting.second_root_category_id,
        second_period: @second_period_for_report
      ).call

      @next_month = @reference_month.next_month.beginning_of_month
      @expense_roots = Current.family.categories.expenses.roots.alphabetically

      @planning_params = planning_params_hash
      @run_rate_report_lines = run_rate_report_lines
      @reference_days_for_run_rate = reference_days_for_run_rate
      @planner = build_planner if @setting.run_rate_root_category_id.present?

      @snapshots = Current.family.monthly_planning_snapshots.chronological.limit(36)
    end

    def settings_params
      params.require(:family_monthly_planning_setting).permit(
        :first_root_category_id,
        :second_root_category_id,
        :run_rate_root_category_id,
        :second_root_period_start,
        :second_root_period_end
      )
    end

    def planning_params_hash
      p = params[:planning]&.permit(
        :inflation_percent,
        :previous_month_surplus,
        :simple_fx_rate,
        :tiered_enabled,
        :tier_first_amount_usd,
        :tier_first_ars_per_usd,
        :tier_second_ars_per_usd,
        :second_period_start,
        :second_period_end
      )&.to_h
      p ||= {}
      p[:inflation_percent] = (p[:inflation_percent].presence || 0).to_s
      p[:previous_month_surplus] = (p[:previous_month_surplus].presence || 0).to_s
      p[:tiered_enabled] = ActiveModel::Type::Boolean.new.cast(p[:tiered_enabled])
      p[:run_rate] = run_rate_inputs_from_request
      p
    end

    def resolved_second_root_period
      start_d = parse_planning_date(params.dig(:planning, :second_period_start)) || @setting.second_root_period_start
      end_d = parse_planning_date(params.dig(:planning, :second_period_end)) || @setting.second_root_period_end
      return @period if start_d.blank? || end_d.blank?
      return @period if end_d < start_d

      Period.custom(start_date: start_d, end_date: end_d)
    end

    def parse_planning_date(value)
      return if value.blank?

      value.to_date
    rescue ArgumentError, TypeError
      nil
    end

    def run_rate_report_lines
      return [] unless @setting.run_rate_root_category_id.present?

      if @setting.run_rate_root_category_id == @setting.first_root_category_id
        @report.first_root_lines
      else
        @report.second_root_lines
      end
    end

    def reference_days_for_run_rate
      return unless @setting.run_rate_root_category_id.present?

      if @setting.run_rate_root_category_id == @setting.first_root_category_id
        @period.days
      else
        @second_period_for_report.days
      end
    end

    def run_rate_inputs_from_request
      raw = params.dig(:planning, :run_rate)
      return {} if raw.blank?

      hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
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

    def build_planner
      run_spent = if @setting.run_rate_root_category_id == @setting.first_root_category_id
        @report.first_root_total
      else
        @report.second_root_total
      end
      other_spent = if @setting.run_rate_root_category_id == @setting.first_root_category_id
        @report.second_root_total
      else
        @report.first_root_total
      end

      line_hashes = @run_rate_report_lines.map do |l|
        { category_id: l.category_id, category_name: l.category_name, baseline_spent: l.total }
      end

      MonthlyPlanning::NextMonthPlanner.new(
        reference_month: @reference_month,
        next_month: @next_month,
        spent_run_rate_root: run_spent,
        spent_other_root: other_spent,
        inflation_percent: planning_params_hash[:inflation_percent],
        previous_month_surplus: planning_params_hash[:previous_month_surplus],
        as_of_date: Date.current,
        simple_fx_rate: planning_params_hash[:simple_fx_rate].presence,
        tiered_enabled: planning_params_hash[:tiered_enabled],
        tier_first_amount_usd: planning_params_hash[:tier_first_amount_usd].presence,
        tier_first_ars_per_usd: planning_params_hash[:tier_first_ars_per_usd].presence,
        tier_second_ars_per_usd: planning_params_hash[:tier_second_ars_per_usd].presence,
        run_rate_lines: line_hashes.presence,
        reference_days_for_run_rate: @reference_days_for_run_rate,
        run_rate_line_inputs: planning_params_hash[:run_rate] || {}
      ).call
    end

    def snapshot_inputs_from_request
      planning_params_hash.merge(
        "first_root_category_id" => @setting.first_root_category_id,
        "second_root_category_id" => @setting.second_root_category_id,
        "run_rate_root_category_id" => @setting.run_rate_root_category_id,
        "second_root_period_start" => @setting.second_root_period_start&.to_s,
        "second_root_period_end" => @setting.second_root_period_end&.to_s,
        "second_period_start" => @second_period_start_value,
        "second_period_end" => @second_period_end_value
      )
    end

    def snapshot_outputs_from_planner
      return {} unless @planner

      line_items = @planner.run_rate_line_items.map do |i|
        {
          "category_id" => i.category_id,
          "category_name" => i.category_name,
          "baseline_spent" => i.baseline_spent.to_s,
          "inflation_percent" => i.inflation_percent.to_s,
          "use_manual" => i.use_manual,
          "manual_next_month_amount" => i.manual_next_month_amount.to_s,
          "projected_amount" => i.projected_amount.to_s,
          "mode" => i.mode.to_s
        }
      end

      {
        "projected_run_rate_spend" => @planner.projected_run_rate_spend.to_s,
        "adjusted_projected_run_rate_spend" => @planner.adjusted_projected_run_rate_spend.to_s,
        "run_rate_days_next_month" => @planner.run_rate_days_next_month.to_s,
        "next_month_days_elapsed" => @planner.next_month_days_elapsed.to_s,
        "combined_need_domestic" => @planner.combined_need_domestic.to_s,
        "simple_fx_amount_target_currency" => @planner.simple_fx_amount_target_currency&.to_s,
        "tiered_breakdown" => @planner.tiered_breakdown,
        "uses_line_breakdown" => @planner.uses_line_breakdown,
        "run_rate_line_items" => line_items,
        "pace_reference_days" => @planner.pace_reference_days.to_s
      }.compact
    end
end
