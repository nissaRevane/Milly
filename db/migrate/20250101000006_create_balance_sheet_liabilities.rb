class CreateBalanceSheetLiabilities < ActiveRecord::Migration[8.0]
  def change
    create_table :balance_sheet_liabilities do |t|
      t.references :balance_sheet, null: false, foreign_key: true
      t.references :liability, null: false, foreign_key: true
      t.decimal :remaining_capital, precision: 15, scale: 2, null: false, default: 0
      t.timestamps
    end

    add_index :balance_sheet_liabilities, [:balance_sheet_id, :liability_id], unique: true, name: "idx_bs_liabilities_on_bs_and_liability"
  end
end
