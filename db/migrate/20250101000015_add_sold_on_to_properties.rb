class AddSoldOnToProperties < ActiveRecord::Migration[8.0]
  # La date de vente d'un bien, optionnelle comme sa date d'acquisition : un bien encore
  # détenu n'en a pas, et c'est le cas de tous ceux déjà enregistrés. Elle donne, avec
  # +acquired_on+, la période par défaut des actifs et passifs rattachés au bien
  # (voir Lifespanable).
  def change
    add_column :properties, :sold_on, :date
  end
end
