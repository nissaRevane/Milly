class AddOwnershipShareToAssetsAndLiabilities < ActiveRecord::Migration[8.0]
  def change
    add_column :assets, :ownership_share, :decimal, precision: 5, scale: 2, default: "100.0", null: false
    add_column :liabilities, :ownership_share, :decimal, precision: 5, scale: 2, default: "100.0", null: false
  end
end
