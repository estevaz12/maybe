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
    result = Family::DataImporter.new(@target_family).import_from_zip_io(zip, replace_rules: false)
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
    result = Family::DataImporter.new(target).import_from_zip_io(zip, replace_rules: true)
    assert result.success, result.error_message

    assert_nil Rule.find_by(id: existing.id)
    assert_equal 1, target.rules.count
    assert_equal "Only this", target.rules.sole.name
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
