class ClearMeaninglessPropertyLinks < ActiveRecord::Migration[8.0]
  # Un bien ne porte plus que les lignes qui lui appartiennent vraiment : son propre actif
  # (asset_type real_estate = 4), ses crédits immobiliers (liability_type real_estate_loan
  # = 0) et les dépôts de garantie de ses locataires (security_deposit = 2) — voir
  # PropertyLinkable. Les rattachements que l'ancien formulaire acceptait pour les autres
  # types sont effacés : sans cela ces lignes seraient invalides, donc immodifiables depuis
  # l'écran, et elles continueraient de gonfler le « Brut » du bien dans l'onglet Immobilier.
  #
  # Valeurs d'enum écrites en dur : une migration ne dépend pas des modèles, qui bougent.
  def up
    execute "UPDATE assets SET property_id = NULL WHERE property_id IS NOT NULL AND asset_type <> 4"
    execute "UPDATE liabilities SET property_id = NULL WHERE property_id IS NOT NULL AND liability_type NOT IN (0, 2)"
  end

  # Rien à défaire : les rattachements effacés ne sont plus connus de personne, et revenir à
  # l'ancien code n'en a pas besoin.
  def down
  end
end
