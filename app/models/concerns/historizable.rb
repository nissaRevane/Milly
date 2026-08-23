# Une ligne, actif ou dette, lue dans le temps : son montant, bilan par bilan.
#
# La fiche d'une ligne pose une question que le bilan ne pose pas — celle-ci, prise seule,
# monte-t-elle ou descend-elle ? — et il n'y a qu'une chose à lire pour y répondre : la suite
# des montants que les bilans lui ont donnés.
#
# Le montant est toujours le montant DÉTENU, quote-part appliquée, tel que le bilan l'affiche
# (voir BalanceSheetAsset#owned_value) : une même ligne ne peut pas valoir deux sommes
# différentes selon la page qui la lit.
#
# Chaque modèle dit où sont ses lignes de bilan et comment s'y lit un montant — les deux
# seules choses qui diffèrent d'un côté du bilan à l'autre.
module Historizable
  extend ActiveSupport::Concern

  # Le montant de la ligne dans UN bilan.
  ValuePoint = Struct.new(:balance_sheet, :amount, keyword_init: true) do
    def closing_date
      balance_sheet.closing_date
    end
  end

  # L'histoire d'une ligne, du bilan le plus ancien au plus récent, et les deux reculs sur
  # lesquels sa fiche la lit : le bilan précédent et celui d'il y a un an.
  #
  # Les variations viennent de BalanceSheet.variation_between, comme partout ailleurs : un
  # même écart ne peut pas s'écrire d'une façon sur une fiche et d'une autre sur une synthèse.
  ValueHistory = Struct.new(:points, keyword_init: true) do
    delegate :any?, :empty?, :size, to: :points

    def current
      points.last
    end

    def previous
      points[-2]
    end

    # nil tant que l'histoire ne remonte pas à un an : la fiche affiche alors un tiret plutôt
    # qu'une progression de trois mois annoncée comme annuelle.
    def year_ago
      return nil if current.nil?

      BalanceSheet.a_year_before(points, current)
    end

    def since_previous
      variation_from(previous)
    end

    def over_a_year
      variation_from(year_ago)
    end

    # La courbe, dans la forme que line_chart attend : un couple [date, montant] par bilan.
    def series
      points.map { |point| [point.closing_date, point.amount] }
    end

    private

    def variation_from(point)
      return nil if point.nil?

      BalanceSheet.variation_between(point.amount, current.amount)
    end
  end

  # L'histoire de cette ligne. Les bilans sont chargés avec les lignes : la fiche trace toute
  # la série, et une requête par point la ferait payer à chaque clôture de plus.
  def value_history
    points = historized_lines
      .joins(:balance_sheet).includes(:balance_sheet)
      .order("balance_sheets.closing_date")
      .map { |line| ValuePoint.new(balance_sheet: line.balance_sheet, amount: historized_amount(line)) }

    ValueHistory.new(points: points)
  end
end
