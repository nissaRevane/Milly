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
    @year_ago = BalanceSheet.a_year_before(@timeline, @current)

    @equity_variation = @previous && BalanceSheet.variation_between(@previous.equity, @current.equity)
    @yearly_variation = @year_ago && BalanceSheet.variation_between(@year_ago.equity, @current.equity)

    sheet = @current.balance_sheet
    # La LTV globale du dernier bilan, lue exactement comme l'onglet Immobilier la lit :
    # même positions filtrées, mêmes totaux, donc jamais deux chiffres pour un même bilan.
    @real_estate_total = sheet.real_estate_totals_by_usage(sheet.real_estate_positions)[:total]

    # Les deux aires empilées. Elles portent le même axe que la courbe des fonds propres, et
    # coûtent une requête agrégée chacune : le nombre de bilans ne change pas la charge.
    sheets = @timeline.map(&:balance_sheet)
    @dates = @timeline.map(&:closing_date)
    @assets_breakdown = BalanceSheet.assets_breakdown_for(sheets)
    @liabilities_breakdown = BalanceSheet.liabilities_breakdown_for(sheets)
  end
end
