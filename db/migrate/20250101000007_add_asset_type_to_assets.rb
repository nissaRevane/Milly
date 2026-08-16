class AddAssetTypeToAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :assets, :asset_type, :integer, null: false, default: 0
  end
end
