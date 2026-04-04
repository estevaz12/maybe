# frozen_string_literal: true

class CreateMonthlyPlanningTables < ActiveRecord::Migration[7.2]
  def change
    create_table :family_monthly_planning_settings, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.uuid :first_root_category_id
      t.uuid :second_root_category_id
      t.uuid :run_rate_root_category_id
      t.timestamps
    end

    add_foreign_key :family_monthly_planning_settings, :categories, column: :first_root_category_id
    add_foreign_key :family_monthly_planning_settings, :categories, column: :second_root_category_id
    add_foreign_key :family_monthly_planning_settings, :categories, column: :run_rate_root_category_id

    create_table :monthly_planning_snapshots, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.date :reference_month, null: false
      t.jsonb :inputs, null: false, default: {}
      t.jsonb :outputs, null: false, default: {}
      t.timestamps
    end

    add_index :monthly_planning_snapshots, [ :family_id, :reference_month ]
  end
end
