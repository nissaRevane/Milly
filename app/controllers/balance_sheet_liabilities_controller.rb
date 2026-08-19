class BalanceSheetLiabilitiesController < ApplicationController
  before_action :set_balance_sheet
  before_action :set_balance_sheet_liability, only: [:edit, :update, :destroy]
  before_action :set_available_liabilities, only: [:new, :create, :edit, :update]

  # remaining_capital: nil écarte le défaut de colonne (0.0) : un « 0,0 » pré-rempli est
  # un montant que personne n'a saisi, et il empêcherait le capital restant dû suggéré
  # de s'installer dans un champ vide (voir le contrôleur Stimulus suggested-value).
  def new
    @balance_sheet_liability = @balance_sheet.balance_sheet_liabilities.build(remaining_capital: nil)
  end

  def create
    @balance_sheet_liability = @balance_sheet.balance_sheet_liabilities.build(balance_sheet_liability_params)
    if @balance_sheet_liability.save
      redirect_to @balance_sheet, notice: t("flash.balance_sheet_liabilities.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @balance_sheet_liability.update(balance_sheet_liability_params)
      redirect_to @balance_sheet, notice: t("flash.balance_sheet_liabilities.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @balance_sheet_liability.destroy
    redirect_to @balance_sheet, notice: t("flash.balance_sheet_liabilities.destroyed"), status: :see_other
  end

  private

  def set_balance_sheet
    @balance_sheet = current_user.balance_sheets.find(params[:balance_sheet_id])
  end

  def set_balance_sheet_liability
    @balance_sheet_liability = @balance_sheet.balance_sheet_liabilities.find(params[:id])
  end

  # Les passifs déjà présents dans le bilan ne doivent pas être proposés,
  # à l'exception de celui de la ligne en cours d'édition. Ceux qui n'existaient pas au mois
  # de la clôture non plus : un prêt soldé avant, ou souscrit après, ne pèse pas sur ce
  # bilan-là (voir Lifespanable).
  def set_available_liabilities
    used_liability_ids = @balance_sheet.balance_sheet_liabilities.pluck(:liability_id)
    used_liability_ids -= [@balance_sheet_liability.liability_id] if @balance_sheet_liability&.liability_id

    unused = current_user.liabilities.where.not(id: used_liability_ids)
    offered = unused.available_on(@balance_sheet.closing_date)
    # Le passif de la ligne en cours d'édition reste proposé même hors période : voir
    # BalanceSheetAssetsController#set_available_assets.
    if @balance_sheet_liability&.liability_id
      offered = offered.or(unused.where(id: @balance_sheet_liability.liability_id))
    end

    @available_liabilities = offered.order(:name)
  end

  def balance_sheet_liability_params
    params.require(:balance_sheet_liability).permit(:liability_id, :remaining_capital)
  end
end
