class RemoveRiskLevelFromAssetsAndLiabilities < ActiveRecord::Migration[8.0]
  # Le niveau de risque disparaît : il se saisissait sur chaque actif et chaque dette, mais
  # rien ne s'en servait — ni un calcul, ni une décision. Il ne colorait qu'une pastille et
  # une ligne de la synthèse, là où le type dit déjà ce qu'est la ligne.
  #
  # La colonne se recrée telle qu'elle était (défaut « Faible ») si l'on revient en arrière,
  # mais les niveaux saisis, eux, sont perdus : personne ne les lisait.
  def change
    remove_column :assets, :risk_level, :integer, null: false, default: 0
    remove_column :liabilities, :risk_level, :integer, null: false, default: 0
  end
end
