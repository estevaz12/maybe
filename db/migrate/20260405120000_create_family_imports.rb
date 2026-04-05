class CreateFamilyImports < ActiveRecord::Migration[7.2]
  def change
    create_table :family_imports, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.timestamps
    end
  end
end
