class AddLifespanToAssetsAndLiabilities < ActiveRecord::Migration[8.0]
  # La période d'existence d'un actif ou d'une dette, les deux bornes optionnelles : une
  # ligne sans bornes existe de tout temps, et c'est le cas de toutes celles déjà
  # enregistrées. Elle décide des lignes qu'un bilan peut se voir proposer
  # (voir Lifespanable#available_on?).
  def change
    add_column :assets, :started_on, :date
    add_column :assets, :ended_on, :date
    add_column :liabilities, :started_on, :date
    add_column :liabilities, :ended_on, :date

    # Les lignes déjà rattachées à un bien reprennent sa date d'acquisition, comme le fait
    # désormais toute ligne rattachée à sa création (voir Lifespanable) : sans cette reprise
    # la règle ne vaudrait que pour l'avenir, et un bien acheté l'an dernier resterait
    # proposé aux bilans clos avant son achat. Rien à reprendre pour la borne de fin : la
    # date de vente d'un bien vient d'apparaître, aucun bien n'en porte encore.
    #
    # Les lignes déjà inscrites dans un bilan y restent : la période ne filtre que ce qu'un
    # bilan se voit proposer (voir BalanceSheetAsset#asset_within_its_lifespan).
    reversible do |dir|
      dir.up do
        %w[assets liabilities].each do |table|
          execute <<~SQL.squish
            UPDATE #{table} SET started_on = properties.acquired_on
            FROM properties
            WHERE #{table}.property_id = properties.id AND properties.acquired_on IS NOT NULL
          SQL
        end
      end
    end
  end
end
