# frozen_string_literal: true

class MonthlyPlanningSnapshot < ApplicationRecord
  belongs_to :family

  validates :reference_month, presence: true
  validate :reference_month_is_beginning_of_month

  scope :chronological, -> { order(reference_month: :desc, created_at: :desc) }

  private

    def reference_month_is_beginning_of_month
      return if reference_month.blank?
      unless reference_month == reference_month.beginning_of_month
        errors.add(:reference_month, "must be the first day of a month")
      end
    end
end
