# frozen_string_literal: true

class RemoveSecondRootPeriodFromFamilyMonthlyPlanningSettings < ActiveRecord::Migration[7.2]
  def change
    remove_column :family_monthly_planning_settings, :second_root_period_start, :date
    remove_column :family_monthly_planning_settings, :second_root_period_end, :date
  end
end
