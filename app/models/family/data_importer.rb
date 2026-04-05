require "zip"
require "stringio"

class Family::DataImporter
  Result = Struct.new(:success, :error_message, keyword_init: true) do
    def self.ok
      new(success: true, error_message: nil)
    end

    def self.fail(message)
      new(success: false, error_message: message)
    end
  end

  ImportError = Class.new(StandardError)

  def initialize(family)
    @family = family
    @category_id_map = {}
    @tag_id_map = {}
    @merchant_id_map = {}
  end

  # @param io [IO, StringIO] readable zip bytes
  # @param replace_rules [Boolean]
  def import_from_zip_io(io, replace_rules: false)
    io.rewind if io.respond_to?(:rewind)
    buffer = io.respond_to?(:read) ? io.read : io.to_s
    return Result.fail("File is empty") if buffer.blank?

    # Do not use the block form of open_buffer — it calls write_buffer after the block and mutates the buffer.
    zip_file = Zip::File.open_buffer(StringIO.new(buffer))
    entry = zip_file.find_entry("all.ndjson")
    return Result.fail("Missing all.ndjson in zip") unless entry

    ndjson = zip_file.read(entry)
    zip_file.close
    import_from_ndjson(ndjson, replace_rules: replace_rules)
  rescue Zip::Error
    Result.fail("Invalid or corrupted zip file")
  rescue JSON::ParserError => e
    Result.fail("Invalid JSON in all.ndjson: #{e.message}")
  rescue ImportError => e
    Result.fail(e.message)
  rescue ActiveRecord::RecordInvalid => e
    Result.fail(e.record.errors.full_messages.to_sentence)
  rescue ActiveRecord::RecordNotUnique => e
    Result.fail("Database conflict: #{e.message}")
  end

  private

    def import_from_ndjson(ndjson, replace_rules:)
      records_by_type = Hash.new { |h, k| h[k] = [] }
      ndjson.each_line do |line|
        line = line.strip
        next if line.empty?

        obj = JSON.parse(line)
        records_by_type[obj["type"]] << obj["data"]
      end

      ActiveRecord::Base.transaction do
        import_categories(records_by_type["Category"] || [])
        import_tags(records_by_type["Tag"] || [])
        import_merchants(records_by_type["Merchant"] || [])
        import_rules(records_by_type["Rule"] || [], replace_rules: replace_rules)
      end

      Result.ok
    end

    def import_categories(datas)
      datas = datas.map { |d| d.with_indifferent_access }
      return if datas.empty?

      loop do
        before_size = @category_id_map.size
        datas.each do |data|
          old_id = data[:id].to_s
          next if @category_id_map[old_id]

          parent_old = data[:parent_id]
          if parent_old.present? && !@category_id_map[parent_old.to_s]
            next
          end

          parent_record =
            if parent_old.present?
              @family.categories.find_by(id: @category_id_map[parent_old.to_s])
            end

          category = @family.categories.find_or_initialize_by(name: data[:name].to_s)
          category.color = data[:color] if data[:color].present?
          category.lucide_icon = data[:lucide_icon] if data[:lucide_icon].present?
          category.classification = data[:classification] if data[:classification].present?
          category.parent = parent_record if parent_record
          category.save!
          @category_id_map[old_id] = category.id
        end

        unresolved = datas.reject { |d| @category_id_map[d[:id].to_s] }
        break if unresolved.empty?

        if @category_id_map.size == before_size
          raise ImportError, "Could not resolve category hierarchy (#{unresolved.size} categories left)"
        end
      end
    end

    def import_tags(datas)
      datas.each do |raw|
        data = raw.with_indifferent_access
        old_id = data[:id].to_s
        tag = @family.tags.find_or_initialize_by(name: data[:name].to_s)
        tag.color = data[:color] if data[:color].present?
        tag.save!
        @tag_id_map[old_id] = tag.id
      end
    end

    def import_merchants(datas)
      datas.each do |raw|
        data = raw.with_indifferent_access
        # as_json omits STI `type` in some Rails versions; only skip non-family merchants when explicit.
        next if data[:type].present? && data[:type].to_s != "FamilyMerchant"

        old_id = data[:id].to_s
        merchant = @family.merchants.find_or_initialize_by(name: data[:name].to_s)
        merchant.logo_url = data[:logo_url] if data.key?(:logo_url)
        merchant.website_url = data[:website_url] if data.key?(:website_url)
        merchant.save!
        @merchant_id_map[old_id] = merchant.id
      end
    end

    def import_rules(datas, replace_rules:)
      @family.rules.destroy_all if replace_rules

      datas.each do |raw|
        data = raw.with_indifferent_access
        rule = @family.rules.build(
          resource_type: data[:resource_type].to_s,
          name: data[:name].presence,
          effective_date: parse_date(data[:effective_date]),
          active: data.key?(:active) ? ActiveModel::Type::Boolean.new.cast(data[:active]) : false
        )

        Array(data[:conditions]).each do |cond_data|
          build_root_condition(rule, cond_data.with_indifferent_access)
        end

        Array(data[:actions]).each do |act_data|
          act = act_data.with_indifferent_access
          rule.actions.build(
            action_type: act[:action_type].to_s,
            value: remap_action_value(act[:action_type].to_s, act[:value])
          )
        end

        rule.save!
      end
    end

    def parse_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    end

    def build_root_condition(rule, cond_data)
      if cond_data[:condition_type].to_s == "compound"
        parent = rule.conditions.build(
          condition_type: "compound",
          operator: cond_data[:operator].to_s,
          value: nil
        )
        Array(cond_data[:sub_conditions]).each do |sub_raw|
          sub = sub_raw.with_indifferent_access
          parent.sub_conditions.build(
            condition_type: sub[:condition_type].to_s,
            operator: sub[:operator].to_s,
            value: remap_condition_value(sub[:condition_type].to_s, sub[:value])
          )
        end
      else
        rule.conditions.build(
          condition_type: cond_data[:condition_type].to_s,
          operator: cond_data[:operator].to_s,
          value: remap_condition_value(cond_data[:condition_type].to_s, cond_data[:value])
        )
      end
    end

    def remap_condition_value(condition_type, value)
      return value if value.blank?

      str = value.to_s
      case condition_type
      when "transaction_merchant"
        @merchant_id_map[str] || str
      else
        str
      end
    end

    def remap_action_value(action_type, value)
      return value if value.blank?

      str = value.to_s
      case action_type
      when "set_transaction_category"
        (@category_id_map[str] || str).to_s
      when "set_transaction_tags"
        (@tag_id_map[str] || str).to_s
      when "set_transaction_merchant"
        (@merchant_id_map[str] || str).to_s
      else
        str
      end
    end
end
