class AddReplaceRulesToFamilyImports < ActiveRecord::Migration[7.2]
  def change
    add_column :family_imports, :replace_rules, :boolean, default: false, null: false
  end
end
