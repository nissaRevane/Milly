class AddAmortizationToLiabilities < ActiveRecord::Migration[8.0]
  # Caractéristiques d'amortissement d'un crédit immobilier, toutes optionnelles : les
  # passifs déjà créés n'en portent aucune, et un passif reste utilisable au bilan sans
  # elles. Le modèle impose le tout-ou-rien : soit les sept champs, soit aucun.
  def change
    add_column :liabilities, :borrowed_capital, :decimal, precision: 15, scale: 2
    add_column :liabilities, :annual_rate, :decimal, precision: 6, scale: 3
    add_column :liabilities, :duration_months, :integer
    add_column :liabilities, :monthly_payment, :decimal, precision: 15, scale: 2
    add_column :liabilities, :first_payment_on, :date
    add_column :liabilities, :first_payment_principal, :decimal, precision: 15, scale: 2
    add_column :liabilities, :first_payment_interest, :decimal, precision: 15, scale: 2
  end
end
