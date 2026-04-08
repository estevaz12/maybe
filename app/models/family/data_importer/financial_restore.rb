# frozen_string_literal: true

# Full financial restore from Family::DataExporter NDJSON (accounts, entries, budgets).
# Included by Family::DataImporter; relies on metadata import having run first (category/tag/merchant maps).
module Family::DataImporter::FinancialRestore
  extend ActiveSupport::Concern

  private

    def import_full_scope(records_by_type, replace_rules:, replace_financial_data:)
      cats = records_by_type["Category"] || []
      snaps = records_by_type["MonthlyPlanningSnapshot"] || []
      if cats.empty? && snaps.any?
        raise Family::DataImporter::ImportError,
          "This zip has no category data. Use a full Maybe data export so category IDs in snapshots can be remapped."
      end

      import_categories(cats)
      import_tags(records_by_type["Tag"] || [])
      import_merchants(records_by_type["Merchant"] || [])
      import_rules(records_by_type["Rule"] || [], replace_rules: replace_rules)
      import_family_monthly_planning_setting(records_by_type["FamilyMonthlyPlanningSetting"])
      import_monthly_planning_snapshots(snaps)

      import_financial_from_export_if_present!(records_by_type, replace_financial_data: replace_financial_data)
    end

    def import_financial_from_export_if_present!(records_by_type, replace_financial_data:)
      account_rows = records_by_type["Account"] || []
      return if account_rows.empty?

      @account_id_map = {}
      @security_id_map = {}
      @transaction_id_map = {}
      @budget_id_map = {}

      if @family.accounts.exists?
        unless replace_financial_data
          raise Family::DataImporter::ImportError,
            "This family already has accounts. Enable \"Delete existing accounts, entries, and budgets\" on the import form, or use a family with no accounts."
        end
        @family.budgets.destroy_all
        @family.accounts.destroy_all
      end

      import_accounts_from_ndjson!(account_rows)
      build_security_id_map!(records_by_type["Trade"] || [])
      import_valuations_from_ndjson!(records_by_type["Valuation"] || [])
      import_transactions_from_ndjson!(records_by_type["Transaction"] || [])
      import_trades_from_ndjson!(records_by_type["Trade"] || [])
      import_transfers_from_ndjson!(records_by_type["Transfer"] || [])
      import_budgets_from_ndjson!(records_by_type["Budget"] || [], records_by_type["BudgetCategory"] || [])

      sync_restored_accounts!
    end

    def import_accounts_from_ndjson!(datas)
      datas.each do |raw|
        data = raw.with_indifferent_access
        old_id = data[:id].to_s
        type = data[:accountable_type].to_s
        klass = Accountable.from_type(type)
        raise Family::DataImporter::ImportError, "Unknown accountable type: #{type}" unless klass

        acc_hash = (data[:accountable] || {}).with_indifferent_access
        permitted = acc_hash.slice(*klass.column_names.map(&:to_sym))
        accountable = klass.new(permitted.except(:id).to_h)

        status = data[:status].to_s.presence_in(%w[active draft disabled pending_deletion]) || "active"

        account = @family.accounts.build(
          name: data[:name].to_s,
          balance: data[:balance],
          currency: data[:currency].to_s,
          subtype: data[:subtype],
          status: status,
          cash_balance: data[:cash_balance].presence || data[:balance],
          plaid_account_id: nil,
          import_id: nil,
          accountable: accountable
        )
        account.save!
        @account_id_map[old_id] = account.id
      end
    end

    def build_security_id_map!(trade_datas)
      trade_datas.each do |raw|
        data = raw.with_indifferent_access
        old_sec = data[:security_id].to_s
        next if old_sec.blank? || @security_id_map[old_sec]

        ticker = data[:ticker].to_s.strip
        raise Family::DataImporter::ImportError, "Trade is missing a ticker (security #{old_sec})" if ticker.blank?

        security = Security::Resolver.new(ticker).resolve
        raise Family::DataImporter::ImportError, "Could not resolve security for ticker #{ticker}" unless security

        @security_id_map[old_sec] = security.id
      end
    end

    def import_valuations_from_ndjson!(datas)
      datas.sort_by { |d| [ d["date"].to_s, d["created_at"].to_s ] }.each do |raw|
        data = raw.with_indifferent_access
        account_id = @account_id_map[data[:account_id].to_s]
        raise Family::DataImporter::ImportError, "Valuation references unknown exported account #{data[:account_id]}" unless account_id

        account = @family.accounts.find(account_id)
        kind = data[:kind].to_s.presence_in(Valuation.defined_enums["kind"].keys) || "reconciliation"

        account.entries.create!(
          date: parse_export_date!(data[:date]),
          name: data[:name].to_s,
          amount: data[:amount],
          currency: data[:currency].to_s,
          notes: nil,
          excluded: false,
          plaid_id: nil,
          entryable: Valuation.new(kind: kind)
        )
      end
    end

    def import_transactions_from_ndjson!(datas)
      datas.sort_by { |d| [ d["date"].to_s, d["created_at"].to_s ] }.each do |raw|
        data = raw.with_indifferent_access
        old_tid = data[:id].to_s
        account_id = @account_id_map[data[:account_id].to_s]
        raise Family::DataImporter::ImportError, "Transaction #{old_tid} references unknown exported account #{data[:account_id]}" unless account_id

        account = @family.accounts.find(account_id)
        kind = data[:kind].to_s.presence_in(Transaction.defined_enums["kind"].keys) || "standard"

        category_id = remap_optional_fk(data[:category_id], @category_id_map)
        merchant_id = remap_optional_fk(data[:merchant_id], @merchant_id_map)

        txn = Transaction.new(kind: kind, category_id: category_id, merchant_id: merchant_id)
        entry = account.entries.build(
          date: parse_export_date!(data[:date]),
          name: data[:name].to_s,
          amount: data[:amount],
          currency: data[:currency].to_s,
          notes: data[:notes],
          excluded: ActiveModel::Type::Boolean.new.cast(data[:excluded]),
          plaid_id: nil,
          entryable: txn
        )
        entry.save!

        @transaction_id_map[old_tid] = entry.entryable_id

        Array(data[:tag_ids]).each do |old_tag_id|
          new_tag_id = @tag_id_map[old_tag_id.to_s]
          next unless new_tag_id

          entry.entryable.taggings.create!(tag_id: new_tag_id)
        end
      end
    end

    def import_trades_from_ndjson!(datas)
      datas.sort_by { |d| [ d["date"].to_s, d["created_at"].to_s ] }.each do |raw|
        data = raw.with_indifferent_access
        account_id = @account_id_map[data[:account_id].to_s]
        raise Family::DataImporter::ImportError, "Trade references unknown exported account #{data[:account_id]}" unless account_id

        sec_old = data[:security_id].to_s
        security_id = @security_id_map[sec_old]
        raise Family::DataImporter::ImportError, "Trade references unknown security #{sec_old}" unless security_id

        security = Security.find(security_id)
        qty = data[:qty].to_d
        trade_type = qty.negative? ? "sell" : "buy"
        name = Trade.build_name(trade_type, qty.abs, security.ticker)

        account = @family.accounts.find(account_id)
        trade = Trade.new(
          qty: qty,
          price: data[:price],
          currency: data[:currency].to_s,
          security_id: security_id
        )
        account.entries.create!(
          date: parse_export_date!(data[:date]),
          name: name,
          amount: data[:amount],
          currency: data[:currency].to_s,
          notes: nil,
          excluded: false,
          plaid_id: nil,
          entryable: trade
        )
      end
    end

    def import_transfers_from_ndjson!(datas)
      datas.each do |raw|
        data = raw.with_indifferent_access
        in_id = @transaction_id_map[data[:inflow_transaction_id].to_s]
        out_id = @transaction_id_map[data[:outflow_transaction_id].to_s]
        unless in_id && out_id
          raise Family::DataImporter::ImportError,
            "Transfer references unknown transactions (inflow #{data[:inflow_transaction_id]}, outflow #{data[:outflow_transaction_id]})"
        end

        status = data[:status].to_s.presence_in(Transfer.defined_enums["status"].keys) || "confirmed"
        transfer = Transfer.new(
          inflow_transaction_id: in_id,
          outflow_transaction_id: out_id,
          status: status
        )
        unless transfer.save
          raise Family::DataImporter::ImportError, "Could not restore transfer: #{transfer.errors.full_messages.to_sentence}"
        end
      end
    end

    def import_budgets_from_ndjson!(budget_rows, bc_rows)
      if budget_rows.any? && @family.budgets.exists?
        @family.budgets.destroy_all
      end

      budget_rows.each do |raw|
        data = raw.with_indifferent_access
        old_id = data[:id].to_s
        budget = @family.budgets.create!(
          start_date: parse_export_date!(data[:start_date]),
          end_date: parse_export_date!(data[:end_date]),
          budgeted_spending: data[:budgeted_spending],
          expected_income: data[:expected_income],
          currency: data[:currency].to_s
        )
        @budget_id_map[old_id] = budget.id
      end

      bc_rows.each do |raw|
        data = raw.with_indifferent_access
        budget_id = @budget_id_map[data[:budget_id].to_s]
        category_id = @category_id_map[data[:category_id].to_s]
        next unless budget_id && category_id

        BudgetCategory.create!(
          budget_id: budget_id,
          category_id: category_id,
          budgeted_spending: data[:budgeted_spending],
          currency: data[:currency].to_s
        )
      end
    end

    def remap_optional_fk(old_uuid, map)
      return nil if old_uuid.blank?
      map[old_uuid.to_s]
    end

    def parse_export_date!(value)
      raise Family::DataImporter::ImportError, "Missing date in export row" if value.blank?

      Date.iso8601(value.to_s.slice(0, 10))
    end

    def sync_restored_accounts!
      @family.accounts.reload.each(&:sync_later)
    end
end
