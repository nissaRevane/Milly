class AddPropertyToAssetsAndLiabilities < ActiveRecord::Migration[8.0]
  # Nullable on purpose: existing assets and liabilities keep working unlinked,
  # so no backfill is required.
  def change
    add_reference :assets, :property, foreign_key: true
    add_reference :liabilities, :property, foreign_key: true
  end
end
