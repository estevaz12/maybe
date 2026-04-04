# frozen_string_literal: true

module MonthlyPlanningHelper
  # When projecting, "other" root is the one that uses prior-month total only (not run-rate).
  def monthly_planning_other_root(setting)
    return unless setting&.run_rate_root_category_id.present?

    if setting.run_rate_root_category_id == setting.first_root_category_id
      setting.second_root
    else
      setting.first_root
    end
  end
end
