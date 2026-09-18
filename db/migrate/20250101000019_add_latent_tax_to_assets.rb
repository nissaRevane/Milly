# La fiscalité latente d'un placement : le taux sur l'actif, la base imposable sur chaque
# ligne de bilan. La base est datée parce qu'elle bouge — un versement de plus l'augmente —
# et qu'un bilan clos doit garder celle qui était la sienne à sa date.
class AddLatentTaxToAssets < ActiveRecord::Migration[8.0]
  def change
    add_column :assets, :tax_rate, :decimal, precision: 5, scale: 2, default: "0.0", null: false
    add_column :balance_sheet_assets, :invested_value, :decimal, precision: 15, scale: 2
  end
end
