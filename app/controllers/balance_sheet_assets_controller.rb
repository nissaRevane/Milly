class BalanceSheetAssetsController < ApplicationController
  before_action :set_balance_sheet
  before_action :set_balance_sheet_asset, only: [:edit, :update, :destroy]

  def new
    @balance_sheet_asset = @balance_sheet.balance_sheet_assets.build
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

  def balance_sheet_asset_params
    params.require(:balance_sheet_asset).permit(:asset_id, :value)
  end
end
