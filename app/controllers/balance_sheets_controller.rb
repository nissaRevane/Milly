class BalanceSheetsController < ApplicationController
  before_action :set_balance_sheet, only: [:show, :edit, :update, :destroy, :summary]

  def index
    @balance_sheets = current_user.balance_sheets.order(closing_date: :desc)
  end

  def show
    @balance_sheet_assets = @balance_sheet.balance_sheet_assets.includes(:asset).order("assets.name")
    @balance_sheet_liabilities = @balance_sheet.balance_sheet_liabilities.includes(:liability).order("liabilities.name")
  end

  def new
    @balance_sheet = current_user.balance_sheets.build(closing_date: Date.today)
  end

  def create
    @balance_sheet = current_user.balance_sheets.build(balance_sheet_params)
    if @balance_sheet.save
      redirect_to @balance_sheet, notice: t("flash.balance_sheets.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @balance_sheet.update(balance_sheet_params)
      redirect_to @balance_sheet, notice: t("flash.balance_sheets.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @balance_sheet.destroy
    redirect_to balance_sheets_path, notice: t("flash.balance_sheets.destroyed"), status: :see_other
  end

  def summary
    @assets_by_risk = @balance_sheet.assets_by_risk_level
    @liabilities_by_risk = @balance_sheet.liabilities_by_risk_level
  end

  private

  def set_balance_sheet
    @balance_sheet = current_user.balance_sheets.find(params[:id])
  end

  def balance_sheet_params
    params.require(:balance_sheet).permit(:closing_date)
  end
end
