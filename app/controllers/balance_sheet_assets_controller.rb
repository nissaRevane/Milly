class BalanceSheetAssetsController < ApplicationController
  before_action :set_balance_sheet
  before_action :set_balance_sheet_asset, only: [:edit, :update, :destroy]
  before_action :set_available_assets, only: [:new, :create, :edit, :update]

  # value: nil écarte le défaut de colonne (0.0) : un « 0,0 » pré-rempli est un montant
  # que personne n'a saisi, et il empêchait la valeur suggérée de s'installer dans un
  # champ vide (voir le contrôleur Stimulus suggested-value).
  def new
    @balance_sheet_asset = @balance_sheet.balance_sheet_assets.build(value: nil)
  end

  def create
    @balance_sheet_asset = @balance_sheet.balance_sheet_assets.build(balance_sheet_asset_params)
    if @balance_sheet_asset.save
      redirect_to @balance_sheet, notice: t("flash.balance_sheet_assets.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @balance_sheet_asset.update(balance_sheet_asset_params)
      redirect_to @balance_sheet, notice: t("flash.balance_sheet_assets.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @balance_sheet_asset.destroy
    redirect_to @balance_sheet, notice: t("flash.balance_sheet_assets.destroyed"), status: :see_other
  end

  private

  def set_balance_sheet
    @balance_sheet = current_user.balance_sheets.find(params[:balance_sheet_id])
  end

  def set_balance_sheet_asset
    @balance_sheet_asset = @balance_sheet.balance_sheet_assets.find(params[:id])
  end

  # Les actifs déjà présents dans le bilan ne doivent pas être proposés,
  # à l'exception de celui de la ligne en cours d'édition. Ceux qui n'existaient pas au mois
  # de la clôture non plus : un bien vendu l'an dernier n'a rien à faire dans un bilan
  # d'aujourd'hui, et l'inverse pour un bien acheté depuis (voir Lifespanable).
  def set_available_assets
    used_asset_ids = @balance_sheet.balance_sheet_assets.pluck(:asset_id)
    used_asset_ids -= [@balance_sheet_asset.asset_id] if @balance_sheet_asset&.asset_id

    unused = current_user.assets.where.not(id: used_asset_ids)
    offered = unused.available_on(@balance_sheet.closing_date)
    # L'actif de la ligne en cours d'édition reste proposé même hors période : un select qui
    # ne contient pas la valeur qu'il affiche la remplacerait au premier enregistrement.
    offered = offered.or(unused.where(id: @balance_sheet_asset.asset_id)) if @balance_sheet_asset&.asset_id

    # :property est chargé pour Asset#suggested_value, que le formulaire lit sur chaque option.
    @available_assets = offered.includes(:property).order(:name)
  end

  def balance_sheet_asset_params
    params.require(:balance_sheet_asset).permit(:asset_id, :value)
  end
end
