# frozen_string_literal: true

class AddSecondRootPeriodToFamilyMonthlyPlanningSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :family_monthly_planning_settings, :second_root_period_start, :date
    add_column :family_monthly_planning_settings, :second_root_period_end, :date
  end
end
