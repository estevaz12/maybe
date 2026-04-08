require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @family = families(:dylan_family)
  end

  test "replacing and destroying" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(categories(:income))

    assert_equal categories(:income), transactions.map { |t| t.reload.category }.uniq.first
  end

  test "replacing with nil should nullify the category" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(nil)

    assert_nil transactions.map { |t| t.reload.category }.uniq.first
  end

  test "subcategory can only be one level deep" do
    category = categories(:subcategory)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      category.subcategories.create!(name: "Invalid category", family: @family)
    end

    assert_equal "Validation failed: Parent can't have more than 2 levels of subcategories", error.message
  end

  test "subcategory keeps its own color instead of parent's" do
    parent = categories(:food_and_drink)
    child_color = "#c44fe9"
    assert parent.color != child_color

    sub = @family.categories.create!(
      name: "Coffee Shops",
      parent: parent,
      color: child_color,
      lucide_icon: "coffee"
    )

    sub.reload
    assert_equal child_color, sub.color
    assert_equal parent.color, parent.reload.color
  end
end
