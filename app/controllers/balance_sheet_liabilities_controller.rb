class BalanceSheetLiabilitiesController < ApplicationController
  before_action :set_balance_sheet
  before_action :set_balance_sheet_liability, only: [:edit, :update, :destroy]

  def new
    @balance_sheet_liability = @balance_sheet.balance_sheet_liabilities.build
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

  def balance_sheet_liability_params
    params.require(:balance_sheet_liability).permit(:liability_id, :remaining_capital)
  end
end
