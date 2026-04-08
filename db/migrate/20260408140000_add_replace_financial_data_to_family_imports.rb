# frozen_string_literal: true

class AddReplaceFinancialDataToFamilyImports < ActiveRecord::Migration[7.2]
  def change
    add_column :family_imports, :replace_financial_data, :boolean, default: false, null: false
  end
end
