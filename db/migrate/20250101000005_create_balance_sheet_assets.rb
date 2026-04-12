class CreateBalanceSheetAssets < ActiveRecord::Migration[8.0]
  def change
    create_table :balance_sheet_assets do |t|
      t.references :balance_sheet, null: false, foreign_key: true
      t.references :asset, null: false, foreign_key: true
      t.decimal :value, precision: 15, scale: 2, null: false, default: 0
      t.timestamps
    end

    add_index :balance_sheet_assets, [:balance_sheet_id, :asset_id], unique: true
  end
end
