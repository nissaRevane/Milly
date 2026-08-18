class BalanceSheetsController < ApplicationController
  SUMMARY_TABS = %w[general real_estate].freeze

  before_action :set_balance_sheet, only: [:show, :edit, :update, :destroy, :summary]

  def index
    @balance_sheets = current_user.balance_sheets.order(closing_date: :desc)
  end

  def show
    @assets_by_type = @balance_sheet.assets_by_type
    @liabilities_by_type = @balance_sheet.liabilities_by_type
  end

  def new
    @source = source_balance_sheet
    @balance_sheet = current_user.balance_sheets.build(closing_date: Date.today)
  end

  def create
    @source = source_balance_sheet
    @balance_sheet = current_user.balance_sheets.build(balance_sheet_params)
    if @balance_sheet.save
      @balance_sheet.copy_lines_from(@source) if @source
      redirect_to @balance_sheet, notice: t("flash.balance_sheets.#{@source ? 'duplicated' : 'created'}")
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
    @tab = SUMMARY_TABS.include?(params[:tab]) ? params[:tab] : "general"

    # Nil on the very first balance sheet: there is nothing to compare it to, and every
    # variation below stays nil so the views drop their evolution column outright.
    @previous = @balance_sheet.previous

    # Navigation only: the header steps to the neighbouring bilans, nothing is measured
    # against @following.
    @following = @balance_sheet.following

    # Each tab is a full server-rendered page: only compute what the active tab shows.
    if @tab == "real_estate"
      @property_positions = @balance_sheet.real_estate_positions
      @real_estate_usage_totals = @balance_sheet.real_estate_totals_by_usage(@property_positions)
      @real_estate_variation = @previous && @balance_sheet.real_estate_variation_against(@previous, @property_positions)
    else
      @assets_by_risk = @balance_sheet.assets_by_risk_level
      @assets_by_type = @balance_sheet.assets_by_type
      @liabilities_by_risk = @balance_sheet.liabilities_by_risk_level
      @liabilities_by_type = @balance_sheet.liabilities_by_type
      @variations = @previous && @balance_sheet.variations_against(@previous)
    end
  end

  private

  def set_balance_sheet
    @balance_sheet = current_user.balance_sheets.find(params[:id])
  end

  def source_balance_sheet
    return if params[:source_id].blank?

    current_user.balance_sheets.find(params[:source_id])
  end

  def balance_sheet_params
    params.require(:balance_sheet).permit(:closing_date)
  end
end
