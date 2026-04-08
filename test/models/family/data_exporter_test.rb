require "test_helper"

class Family::DataExporterTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @other_family = families(:empty)
    @exporter = Family::DataExporter.new(@family)

    # Create some test data for the family
    @account = @family.accounts.create!(
      name: "Test Account",
      accountable: Depository.new,
      balance: 1000,
      currency: "USD"
    )

    @category = @family.categories.create!(
      name: "Test Category",
      color: "#FF0000"
    )

    @tag = @family.tags.create!(
      name: "Test Tag",
      color: "#00FF00"
    )
  end

  test "generates a zip file with all required files" do
    zip_data = @exporter.generate_export

    assert zip_data.is_a?(StringIO)

    # Check that the zip contains all expected files
    expected_files = [ "accounts.csv", "transactions.csv", "trades.csv", "categories.csv", "all.ndjson" ]

    Zip::File.open_buffer(zip_data) do |zip|
      actual_files = zip.entries.map(&:name)
      assert_equal expected_files.sort, actual_files.sort
    end
  end

  test "generates valid CSV files" do
    zip_data = @exporter.generate_export

    Zip::File.open_buffer(zip_data) do |zip|
      # Check accounts.csv
      accounts_csv = zip.read("accounts.csv")
      assert accounts_csv.include?("id,name,type,subtype,balance,currency,created_at")

      # Check transactions.csv
      transactions_csv = zip.read("transactions.csv")
      assert transactions_csv.include?("date,account_name,amount,name,category,tags,notes,currency")

      # Check trades.csv
      trades_csv = zip.read("trades.csv")
      assert trades_csv.include?("date,account_name,ticker,quantity,price,amount,currency")

      # Check categories.csv
      categories_csv = zip.read("categories.csv")
      assert categories_csv.include?("name,color,lucide_icon,parent_category,classification")
    end
  end

  test "generates valid NDJSON file" do
    zip_data = @exporter.generate_export

    Zip::File.open_buffer(zip_data) do |zip|
      ndjson_content = zip.read("all.ndjson")
      lines = ndjson_content.split("\n")

      lines.each do |line|
        assert_nothing_raised { JSON.parse(line) }
      end

      # Check that each line has expected structure
      first_line = JSON.parse(lines.first)
      assert first_line.key?("type")
      assert first_line.key?("data")
    end
  end

  test "includes monthly planning setting and snapshots in ndjson" do
    root_a = @family.categories.create!(name: "MPS Export Root A", color: "#010101", lucide_icon: "circle")
    root_b = @family.categories.create!(name: "MPS Export Root B", color: "#020202", lucide_icon: "square")
    FamilyMonthlyPlanningSetting.create!(
      family: @family,
      first_root_category_id: root_a.id,
      second_root_category_id: root_b.id,
      run_rate_root_category_id: root_a.id
    )
    MonthlyPlanningSnapshot.create!(
      family: @family,
      reference_month: Date.new(2026, 2, 1),
      inputs: { "inflation_percent" => "4" },
      outputs: { root_a.id.to_s => { "total" => "99" } }
    )

    zip_data = @exporter.generate_export
    Zip::File.open_buffer(zip_data) do |zip|
      ndjson_content = zip.read("all.ndjson")
      parsed = ndjson_content.split("\n").map { |l| JSON.parse(l) }
      types = parsed.pluck("type")

      assert_includes types, "FamilyMonthlyPlanningSetting"
      assert_includes types, "MonthlyPlanningSnapshot"

      setting = parsed.find { |o| o["type"] == "FamilyMonthlyPlanningSetting" }["data"]
      assert_equal root_a.id.to_s, setting["first_root_category_id"]
      assert_equal root_b.id.to_s, setting["second_root_category_id"]

      snap = parsed.find { |o| o["type"] == "MonthlyPlanningSnapshot" }["data"]
      assert_equal Date.new(2026, 2, 1), Date.iso8601(snap["reference_month"].to_s).beginning_of_month
      assert_equal "4", snap.dig("inputs", "inflation_percent")
      assert_equal "99", snap.dig("outputs", root_a.id.to_s, "total")
    end
  end

  test "includes transfers in ndjson when family has transfers" do
    checking = @family.accounts.create!(
      name: "Checking T",
      accountable: Depository.new,
      balance: 2000,
      currency: "USD"
    )
    savings = @family.accounts.create!(
      name: "Savings T",
      accountable: Depository.new,
      balance: 500,
      currency: "USD"
    )
    transfer = Transfer::Creator.new(
      family: @family,
      source_account_id: checking.id,
      destination_account_id: savings.id,
      date: Date.new(2026, 3, 10),
      amount: 25
    ).create
    assert transfer.persisted?, transfer.errors.full_messages.join(", ")

    zip_data = @exporter.generate_export
    Zip::File.open_buffer(zip_data) do |zip|
      ndjson_content = zip.read("all.ndjson")
      transfer_lines = ndjson_content.split("\n").map { |l| JSON.parse(l) }.select { |o| o["type"] == "Transfer" }
      data = transfer_lines.find { |o|
        o["data"]["inflow_transaction_id"] == transfer.inflow_transaction_id.to_s
      }&.fetch("data")
      assert data, "expected export to include created transfer"
      assert_equal transfer.outflow_transaction_id.to_s, data["outflow_transaction_id"]
      assert_equal "confirmed", data["status"]
    end
  end

  test "includes rules in ndjson when family has rules" do
    groceries = @family.categories.create!(name: "Export Rule Cat")
    merchant = @family.merchants.create!(name: "Export Merchant", type: "FamilyMerchant")
    Rule.create!(
      family: @family,
      resource_type: "transaction",
      name: "Export test rule",
      effective_date: 1.day.ago.to_date,
      active: false,
      conditions: [ Rule::Condition.new(condition_type: "transaction_merchant", operator: "=", value: merchant.id) ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: groceries.id) ]
    )

    zip_data = @exporter.generate_export
    Zip::File.open_buffer(zip_data) do |zip|
      ndjson_content = zip.read("all.ndjson")
      rule_lines = ndjson_content.split("\n").map { |l| JSON.parse(l) }.select { |o| o["type"] == "Rule" }
      data = rule_lines.find { |o| o.dig("data", "name") == "Export test rule" }&.fetch("data")
      assert data
      assert_equal "transaction", data["resource_type"]
      assert_equal "Export test rule", data["name"]
      assert_equal false, data["active"]
      assert_equal 1, data["conditions"].length
      assert_equal "transaction_merchant", data["conditions"].first["condition_type"]
      assert_equal 1, data["actions"].length
      assert_equal "set_transaction_category", data["actions"].first["action_type"]
    end
  end

  test "only exports data from the specified family" do
    # Create data for another family that should NOT be exported
    other_account = @other_family.accounts.create!(
      name: "Other Family Account",
      accountable: Depository.new,
      balance: 5000,
      currency: "USD"
    )

    other_category = @other_family.categories.create!(
      name: "Other Family Category",
      color: "#0000FF"
    )

    zip_data = @exporter.generate_export

    Zip::File.open_buffer(zip_data) do |zip|
      # Check accounts.csv doesn't contain other family's data
      accounts_csv = zip.read("accounts.csv")
      assert accounts_csv.include?(@account.name)
      refute accounts_csv.include?(other_account.name)

      # Check categories.csv doesn't contain other family's data
      categories_csv = zip.read("categories.csv")
      assert categories_csv.include?(@category.name)
      refute categories_csv.include?(other_category.name)

      # Check NDJSON doesn't contain other family's data
      ndjson_content = zip.read("all.ndjson")
      refute ndjson_content.include?(other_account.id)
      refute ndjson_content.include?(other_category.id)
    end
  end
end
