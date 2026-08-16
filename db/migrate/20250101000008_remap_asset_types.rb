class RemapAssetTypes < ActiveRecord::Migration[8.0]
  # Old: checking_account:0 joint_account:1 savings_account:2 financial_investment:3 real_estate:4
  # New: cash:0 checking_account:1 savings_account:2 financial_investment:3 real_estate:4 receivable:5
  def up
    execute "UPDATE assets SET asset_type = 1 WHERE asset_type IN (0, 1)"
    change_column_default :assets, :asset_type, 1
  end

  # Lossy on purpose: the old enum has no equivalent for cash(0) or receivable(5),
  # so both collapse into the old checking_account(0) alongside the new
  # checking_account(1). Rolling back and forward again is NOT round-trip safe.
  def down
    execute "UPDATE assets SET asset_type = 0 WHERE asset_type = 5"
    execute "UPDATE assets SET asset_type = 0 WHERE asset_type IN (0, 1)"
    change_column_default :assets, :asset_type, 0
  end
end
