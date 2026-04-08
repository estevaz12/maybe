# frozen_string_literal: true

class FamilyMonthlyPlanningSetting < ApplicationRecord
  belongs_to :family
  belongs_to :first_root, class_name: "Category", optional: true, foreign_key: :first_root_category_id
  belongs_to :second_root, class_name: "Category", optional: true, foreign_key: :second_root_category_id
  belongs_to :run_rate_root, class_name: "Category", optional: true, foreign_key: :run_rate_root_category_id

  validate :roots_belong_to_family
  validate :run_rate_matches_a_root
  validate :distinct_roots

  private

    def distinct_roots
      return if first_root_category_id.blank? || second_root_category_id.blank?
      if first_root_category_id == second_root_category_id
        errors.add(:second_root_category_id, "must be different from the first root")
      end
    end

    def roots_belong_to_family
      [ first_root, second_root ].compact.each do |cat|
        if cat.family_id != family_id
          errors.add(:base, "Category must belong to this family")
        end
      end
    end

    def run_rate_matches_a_root
      return if run_rate_root_category_id.blank?
      unless [ first_root_category_id, second_root_category_id ].include?(run_rate_root_category_id)
        errors.add(:run_rate_root, "must be the first or second root category")
      end
    end
end
