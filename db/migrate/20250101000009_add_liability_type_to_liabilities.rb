class AddLiabilityTypeToLiabilities < ActiveRecord::Migration[8.0]
  def change
    add_column :liabilities, :liability_type, :integer, null: false, default: 0
  end
end
