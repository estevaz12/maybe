# frozen_string_literal: true

require "test_helper"

class MonthlyPlanningControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "show monthly planning" do
    get monthly_planning_root_url
    assert_response :success
  end

  test "show with month param" do
    get monthly_planning_url(Budget.date_to_param(Date.new(2026, 2, 1)))
    assert_response :success
  end

  test "preview returns projection html json" do
    family = users(:family_admin).family
    a = family.categories.create!(name: "Preview A", classification: "expense", lucide_icon: "circle")
    b = family.categories.create!(name: "Preview B", classification: "expense", lucide_icon: "circle")
    FamilyMonthlyPlanningSetting.create!(
      family: family,
      first_root: a,
      second_root: b,
      run_rate_root: a
    )

    ref = Date.new(2026, 2, 1)
    get monthly_planning_preview_url(Budget.date_to_param(ref)),
        params: { planning: { inflation_percent: "5", previous_month_surplus: "0" } },
        headers: { "Accept" => "application/json" }

    assert_response :success
    body = JSON.parse(response.body)
    assert body["summary_html"].present?
    assert_match "Estimated total for next month", body["summary_html"]
  end

  test "update settings" do
    family = users(:family_admin).family
    a = family.categories.create!(name: "A", classification: "expense", lucide_icon: "circle")
    b = family.categories.create!(name: "B", classification: "expense", lucide_icon: "circle")

    patch monthly_planning_settings_url,
          params: {
            month_year: Budget.date_to_param(Date.current),
            family_monthly_planning_setting: {
              first_root_category_id: a.id,
              second_root_category_id: b.id,
              run_rate_root_category_id: a.id
            }
          }

    assert_redirected_to monthly_planning_path(Budget.date_to_param(Date.current))
    assert family.reload.family_monthly_planning_setting.present?
  end

  test "create snapshot saves planning inputs and outputs" do
    family = users(:family_admin).family
    a = family.categories.create!(name: "Root A", classification: "expense", lucide_icon: "circle")
    b = family.categories.create!(name: "Root B", classification: "expense", lucide_icon: "circle")
    FamilyMonthlyPlanningSetting.create!(
      family: family,
      first_root: a,
      second_root: b,
      run_rate_root: a
    )

    ref = Date.new(2026, 2, 1)
    assert_difference -> { family.monthly_planning_snapshots.count }, 1 do
      post monthly_planning_snapshots_url,
           params: {
             month_year: Budget.date_to_param(ref),
             planning: {
               inflation_percent: "5",
               simple_fx_rate: "1200"
             }
           }
    end

    assert_redirected_to monthly_planning_path(Budget.date_to_param(ref))
    snap = family.monthly_planning_snapshots.last
    assert_equal ref.beginning_of_month, snap.reference_month
    assert_equal "5", snap.inputs["inflation_percent"]
    assert snap.outputs["combined_need_domestic"].present?
  end

  test "show snapshot" do
    family = users(:family_admin).family
    snap = family.monthly_planning_snapshots.create!(
      reference_month: Date.new(2026, 1, 1),
      inputs: { "inflation_percent" => "3" },
      outputs: { "combined_need_domestic" => "1000.0" }
    )

    get monthly_planning_snapshot_url(snap)
    assert_response :success
    assert_match "Saved snapshot", response.body
    assert_match "Inflation percent", response.body
  end

  test "cannot view another familys snapshot" do
    other_snap = families(:empty).monthly_planning_snapshots.create!(
      reference_month: Date.new(2026, 1, 1),
      inputs: {},
      outputs: {}
    )

    get monthly_planning_snapshot_url(other_snap)
    assert_response :not_found
  end
end
