require "test_helper"
require "stringio"

class Family::DataImporterTest < ActiveSupport::TestCase
  setup do
    @source_family = families(:dylan_family)
    @target_family = families(:empty)
  end

  test "imports categories tags merchants and rules with remapped ids" do
    merchant = @source_family.merchants.create!(name: "Importer Merchant", type: "FamilyMerchant")
    category = @source_family.categories.create!(name: "Importer Category Unique", color: "#112233", lucide_icon: "coffee")
    tag = @source_family.tags.create!(name: "Importer Tag Unique", color: "#445566")

    Rule.create!(
      family: @source_family,
      resource_type: "transaction",
      name: "Importer rule",
      effective_date: 2.days.ago.to_date,
      active: true,
      conditions: [
        Rule::Condition.new(condition_type: "transaction_merchant", operator: "=", value: merchant.id)
      ],
      actions: [
        Rule::Action.new(action_type: "set_transaction_category", value: category.id),
        Rule::Action.new(action_type: "set_transaction_tags", value: tag.id)
      ]
    )

    zip = Family::DataExporter.new(@source_family).generate_export
    zip.rewind
    zf = Zip::File.open_buffer(StringIO.new(zip.read))
    ndjson_raw = zf.read(zf.find_entry("all.ndjson"))
    zf.close
    assert_match(/Importer Merchant/, ndjson_raw, "export should include new merchant name")

    zip.rewind
    result = Family::DataImporter.new(@target_family).import_from_zip_io(zip, replace_rules: false, import_scope: "rules")
    assert result.success, result.error_message

    imported_category = @target_family.categories.find_by!(name: "Importer Category Unique")
    assert_equal "#112233", imported_category.color
    assert_equal "coffee", imported_category.lucide_icon

    imported_merchant = @target_family.merchants.find_by!(name: "Importer Merchant")
    imported_tag = @target_family.tags.find_by!(name: "Importer Tag Unique")

    rule = @target_family.rules.find_by!(name: "Importer rule")
    assert rule.active
    assert_equal imported_merchant.id.to_s, rule.conditions.first.value
    assert_equal imported_category.id.to_s, rule.actions.find_by(action_type: "set_transaction_category").value
    assert_equal imported_tag.id.to_s, rule.actions.find_by(action_type: "set_transaction_tags").value
  end

  test "replace_rules removes existing rules before import" do
    target = families(:dylan_family)
    existing = Rule.create!(
      family: target,
      resource_type: "transaction",
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "=", value: "x") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_name", value: "y") ]
    )

    source = families(:empty)
    category = source.categories.create!(name: "Replace Cat", color: "#000001", lucide_icon: "star")
    Rule.create!(
      family: source,
      resource_type: "transaction",
      name: "Only this",
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "=", value: "a") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: category.id) ]
    )

    zip = Family::DataExporter.new(source).generate_export
    zip.rewind
    result = Family::DataImporter.new(target).import_from_zip_io(zip, replace_rules: true, import_scope: "rules")
    assert result.success, result.error_message

    assert_nil Rule.find_by(id: existing.id)
    assert_equal 1, target.rules.count
    assert_equal "Only this", target.rules.sole.name
  end

  test "categories scope does not import rules" do
    @source_family.categories.create!(name: "Cat Only", color: "#111111", lucide_icon: "star")
    Rule.create!(
      family: @source_family,
      resource_type: "transaction",
      name: "Should not import",
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "=", value: "x") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_name", value: "y") ]
    )

    zip = Family::DataExporter.new(@source_family).generate_export
    zip.rewind
    result = Family::DataImporter.new(@target_family).import_from_zip_io(zip, import_scope: "categories")
    assert result.success, result.error_message

    assert @target_family.categories.find_by(name: "Cat Only")
    assert_nil @target_family.rules.find_by(name: "Should not import")
  end

  test "full scope imports rules and monthly planning in one pass" do
    root_a = @source_family.categories.create!(name: "Full Root A", color: "#050505", lucide_icon: "circle")
    root_b = @source_family.categories.create!(name: "Full Root B", color: "#060606", lucide_icon: "square")
    FamilyMonthlyPlanningSetting.create!(
      family: @source_family,
      first_root_category_id: root_a.id,
      second_root_category_id: root_b.id,
      run_rate_root_category_id: root_a.id
    )
    MonthlyPlanningSnapshot.create!(
      family: @source_family,
      reference_month: Date.new(2026, 7, 1),
      inputs: {},
      outputs: { root_a.id.to_s => { "k" => "v" } }
    )
    Rule.create!(
      family: @source_family,
      resource_type: "transaction",
      name: "Full scope rule",
      conditions: [ Rule::Condition.new(condition_type: "transaction_name", operator: "=", value: "x") ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: root_a.id) ]
    )

    zip = Family::DataExporter.new(@source_family).generate_export
    zip.rewind
    result = Family::DataImporter.new(@target_family).import_from_zip_io(zip, replace_rules: false, import_scope: "full")
    assert result.success, result.error_message

    assert @target_family.rules.find_by!(name: "Full scope rule")
    new_a = @target_family.categories.find_by!(name: "Full Root A")
    snap = @target_family.monthly_planning_snapshots.find_by!(reference_month: Date.new(2026, 7, 1))
    assert_equal "v", snap.outputs[new_a.id.to_s]["k"]
  end

  test "monthly_planning scope imports settings and snapshots with remapped category ids" do
    root_a = @source_family.categories.create!(name: "MPS Imp Root A", color: "#030303", lucide_icon: "circle")
    root_b = @source_family.categories.create!(name: "MPS Imp Root B", color: "#040404", lucide_icon: "square")
    FamilyMonthlyPlanningSetting.create!(
      family: @source_family,
      first_root_category_id: root_a.id,
      second_root_category_id: root_b.id,
      run_rate_root_category_id: root_a.id
    )
    MonthlyPlanningSnapshot.create!(
      family: @source_family,
      reference_month: Date.new(2026, 5, 1),
      inputs: { "inflation_percent" => "2" },
      outputs: { root_a.id.to_s => { "line" => "10" }, "plain" => "ok" }
    )

    zip = Family::DataExporter.new(@source_family).generate_export
    zip.rewind
    result = Family::DataImporter.new(@target_family).import_from_zip_io(zip, import_scope: "monthly_planning")
    assert result.success, result.error_message

    setting = @target_family.family_monthly_planning_setting
    assert setting
    new_a = @target_family.categories.find_by!(name: "MPS Imp Root A")
    new_b = @target_family.categories.find_by!(name: "MPS Imp Root B")
    assert_equal new_a.id, setting.first_root_category_id
    assert_equal new_b.id, setting.second_root_category_id
    assert_equal new_a.id, setting.run_rate_root_category_id

    snap = @target_family.monthly_planning_snapshots.find_by!(reference_month: Date.new(2026, 5, 1))
    assert_equal "2", snap.inputs["inflation_percent"]
    assert_equal "ok", snap.outputs["plain"]
    assert_equal "10", snap.outputs[new_a.id.to_s]["line"]
    refute snap.outputs.key?(root_a.id.to_s)
  end

  test "monthly_planning fails when snapshots exist but zip has no categories" do
    ndjson = {
      "type" => "MonthlyPlanningSnapshot",
      "data" => {
        "reference_month" => "2026-06-01",
        "inputs" => {},
        "outputs" => {}
      }
    }.to_json

    bad_zip = Zip::OutputStream.write_buffer do |z|
      z.put_next_entry("all.ndjson")
      z.write(ndjson)
    end
    bad_zip.rewind

    result = Family::DataImporter.new(@target_family).import_from_zip_io(bad_zip, import_scope: "monthly_planning")
    assert_not result.success
    assert_match(/category data/i, result.error_message)
  end

  test "full import fails when target family already has accounts and replace_financial_data is false" do
    src = Family.create!(name: "Src guard", currency: "USD")
    src.accounts.create!(name: "Only", accountable: Depository.new, balance: 1, currency: "USD")

    zip = Family::DataExporter.new(src).generate_export
    zip.rewind
    result = Family::DataImporter.new(families(:dylan_family)).import_from_zip_io(
      zip,
      import_scope: "full",
      replace_financial_data: false
    )
    assert_not result.success
    assert_match(/already has accounts/i, result.error_message)
  end

  test "full import replaces accounts when replace_financial_data is true" do
    Account.any_instance.stubs(:sync_later)

    src = Family.create!(name: "Src wipe", currency: "USD")
    src.accounts.create!(name: "Imported Acc", accountable: Depository.new, balance: 100, currency: "USD")

    target = families(:empty)
    junk = target.accounts.create!(name: "Junk", accountable: Depository.new, balance: 1, currency: "USD")

    zip = Family::DataExporter.new(src).generate_export
    zip.rewind
    result = Family::DataImporter.new(target).import_from_zip_io(
      zip,
      import_scope: "full",
      replace_financial_data: true
    )
    assert result.success, result.error_message

    assert_nil Account.find_by(id: junk.id)
    assert target.accounts.find_by(name: "Imported Acc")
  end

  test "full import restores transactions trades transfers budgets and valuations" do
    Account.any_instance.stubs(:sync_later)

    src = Family.create!(name: "Src e2e", currency: "USD")
    cat = src.categories.create!(name: "E2E Cat", color: "#111111", lucide_icon: "star")
    checking = src.accounts.create!(name: "E2E Check", accountable: Depository.new, balance: 2000, currency: "USD")
    savings = src.accounts.create!(name: "E2E Save", accountable: Depository.new, balance: 100, currency: "USD")
    inv = src.accounts.create!(name: "E2E Inv", accountable: Investment.new, balance: 0, currency: "USD")

    checking.entries.create!(
      date: Date.new(2026, 4, 1),
      name: "Coffee",
      amount: 5,
      currency: "USD",
      entryable: Transaction.new(kind: :standard, category_id: cat.id)
    )

    Transfer::Creator.new(
      family: src,
      source_account_id: checking.id,
      destination_account_id: savings.id,
      date: Date.new(2026, 4, 2),
      amount: 25
    ).create

    sec = securities(:aapl)
    inv.entries.create!(
      date: Date.new(2026, 4, 3),
      name: "Buy AAPL",
      amount: -100,
      currency: "USD",
      entryable: Trade.new(qty: 1, price: 100, currency: "USD", security_id: sec.id)
    )

    checking.entries.create!(
      date: Date.new(2026, 3, 1),
      name: Valuation.build_reconciliation_name("Depository"),
      amount: 2000,
      currency: "USD",
      entryable: Valuation.new(kind: :reconciliation)
    )

    budget = src.budgets.create!(
      start_date: Date.new(2026, 4, 1).beginning_of_month,
      end_date: Date.new(2026, 4, 30),
      currency: "USD",
      budgeted_spending: 300,
      expected_income: 400
    )
    BudgetCategory.create!(budget: budget, category: cat, budgeted_spending: 50, currency: "USD")

    zip = Family::DataExporter.new(src).generate_export
    zip.rewind

    target = families(:empty)
    result = Family::DataImporter.new(target).import_from_zip_io(zip, import_scope: "full")
    assert result.success, result.error_message

    assert_equal 3, target.accounts.count
    check_t = target.accounts.find_by!(name: "E2E Check")
    assert check_t.transactions.joins(:entry).merge(Entry.where(name: "Coffee")).exists?

    txn_ids = target.transactions.pluck(:id)
    assert Transfer.exists?(
      inflow_transaction_id: txn_ids,
      outflow_transaction_id: txn_ids
    ),
      "expected a restored transfer between exported transactions"

    inv_t = target.accounts.find_by!(name: "E2E Inv")
    assert inv_t.trades.joins(:security).where(securities: { ticker: "AAPL" }).exists?

    assert check_t.entries.valuations.exists?

    assert_equal 1, target.budgets.where(start_date: Date.new(2026, 4, 1).beginning_of_month).count
    assert target.budget_categories.joins(:category).where(categories: { name: "E2E Cat" }).exists?
  end

  test "fails when zip has no all.ndjson" do
    bad_zip = Zip::OutputStream.write_buffer do |z|
      z.put_next_entry("readme.txt")
      z.write("nope")
    end
    bad_zip.rewind

    result = Family::DataImporter.new(@target_family).import_from_zip_io(bad_zip)
    assert_not result.success
    assert_match(/all\.ndjson/, result.error_message)
  end
end
