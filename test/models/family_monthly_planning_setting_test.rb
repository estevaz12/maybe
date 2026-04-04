# frozen_string_literal: true

require "test_helper"

class FamilyMonthlyPlanningSettingTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @a = @family.categories.create!(name: "A", classification: "expense", lucide_icon: "circle")
    @b = @family.categories.create!(name: "B", classification: "expense", lucide_icon: "circle")
  end

  test "run_rate_root must be first or second root" do
    s = FamilyMonthlyPlanningSetting.new(
      family: @family,
      first_root: @a,
      second_root: @b,
      run_rate_root: @family.categories.create!(name: "X", classification: "expense", lucide_icon: "circle")
    )
    assert_not s.valid?
    assert_includes s.errors[:run_rate_root], "must be the first or second root category"
  end

  test "valid when run rate is first root" do
    s = FamilyMonthlyPlanningSetting.create!(
      family: @family,
      first_root: @a,
      second_root: @b,
      run_rate_root: @a
    )
    assert s.persisted?
  end

  test "first and second root must differ" do
    s = FamilyMonthlyPlanningSetting.new(
      family: @family,
      first_root: @a,
      second_root: @a,
      run_rate_root: @a
    )
    assert_not s.valid?
    assert_includes s.errors[:second_root_category_id], "must be different from the first root"
  end
end
