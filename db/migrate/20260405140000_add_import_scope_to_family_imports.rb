class AddImportScopeToFamilyImports < ActiveRecord::Migration[7.2]
  def change
    add_column :family_imports, :import_scope, :string, null: false, default: "rules"
  end
end
