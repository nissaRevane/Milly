# La page d'accueil d'un utilisateur connecté : l'évolution de son patrimoine dans le temps.
#
# Là où balance_sheets#index liste les bilans un par un, le tableau de bord les lit comme une
# série — d'où BalanceSheet.timeline_for, qui ramène les totaux de toute l'histoire en deux
# requêtes plutôt qu'en deux par bilan.
class DashboardController < ApplicationController
  def show
    @timeline = BalanceSheet.timeline_for(current_user.balance_sheets.order(closing_date: :asc))
    @current = @timeline.last
    return if @current.nil?

    @previous = @timeline[-2]
    @year_ago = point_a_year_before(@current)

    @equity_variation = @previous && BalanceSheet.variation_between(@previous.equity, @current.equity)
    @yearly_variation = @year_ago && BalanceSheet.variation_between(@year_ago.equity, @current.equity)

    sheet = @current.balance_sheet
    # La LTV globale du dernier bilan, lue exactement comme l'onglet Immobilier la lit :
    # même positions filtrées, mêmes totaux, donc jamais deux chiffres pour un même bilan.
    @real_estate_total = sheet.real_estate_totals_by_usage(sheet.real_estate_positions)[:total]
    @assets_by_type = sheet.assets_by_type
  end

  private

  # Le bilan sur lequel se lit la variation « sur un an » : le plus récent qui ait au moins
  # un an de recul sur le dernier. Une année calendaire et non 365 jours, pour qu'un bilan au
  # 31/12 se compare au 31/12 précédent même quand une année bissextile s'intercale.
  #
  # nil tant que l'historique ne remonte pas à un an : la carte affiche alors un tiret plutôt
  # qu'une progression mesurée sur trois mois qu'elle annoncerait comme annuelle.
  def point_a_year_before(current)
    threshold = current.closing_date - 1.year

    @timeline.reverse.find { |point| point.closing_date <= threshold }
  end
end
