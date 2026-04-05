# frozen_string_literal: true

module MonthlyPlanning
  # Kill switch via ENV. Unset or blank means enabled (avoids empty-string env from hosts).
  module Feature
    def self.enabled?
      val = ENV["MONTHLY_PLANNING_ENABLED"]
      return true if val.nil? || val.strip.empty?

      ActiveModel::Type::Boolean.new.cast(val.strip)
    end
  end
end
