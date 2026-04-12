class CreateBalanceSheets < ActiveRecord::Migration[8.0]
  def change
    create_table :balance_sheets do |t|
      t.references :user, null: false, foreign_key: true
      t.date :closing_date, null: false
      t.timestamps
    end

    add_index :balance_sheets, [:user_id, :closing_date], unique: true
  end
end
