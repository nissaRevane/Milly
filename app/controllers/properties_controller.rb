class PropertiesController < ApplicationController
  before_action :set_property, only: [:show, :edit, :update, :destroy]

  def index
    @properties = current_user.properties.order(:usage, :name)
  end

  # The fiche of a bien: what it is (address, purchase price, acquisition date) and what
  # it weighs today — its actifs and its dettes, valued on the most recent balance sheet.
  def show
    @assets = @property.assets.order(:asset_type, :name)
    @liabilities = @property.liabilities.order(:liability_type, :name)
    @balance_sheet = current_user.balance_sheets.order(closing_date: :desc).first
    @asset_lines = latest_lines(@balance_sheet&.balance_sheet_assets&.includes(:asset), :asset_id, @assets)
    @liability_lines = latest_lines(@balance_sheet&.balance_sheet_liabilities&.includes(:liability), :liability_id, @liabilities)

    # Reuses the struct the balance sheet aggregates with, so the brut / dette / net /
    # LTV shown here can never drift from the ones on the bilan summary.
    @position = BalanceSheet::PropertyPosition.new(
      property: @property,
      asset_lines: @asset_lines.values,
      liability_lines: @liability_lines.values
    )
  end

  def new
    @property = current_user.properties.build
  end

  def create
    @property = current_user.properties.build(property_params)
    if @property.save
      redirect_to properties_path, notice: t("flash.properties.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @property.update(property_params)
      redirect_to properties_path, notice: t("flash.properties.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @property.destroy
    redirect_to properties_path, notice: t("flash.properties.destroyed"), status: :see_other
  end

  private

  def set_property
    @property = current_user.properties.find(params[:id])
  end

  # The lines of the most recent balance sheet that value the given records, keyed by
  # the record id. A record with no line there is simply absent: it has never been
  # valued, or not on that date, and the view renders an em dash.
  def latest_lines(scope, foreign_key, records)
    return {} if scope.nil? || records.empty?

    scope.where(foreign_key => records.map(&:id)).index_by(&foreign_key)
  end

  def property_params
    params.require(:property).permit(:name, :usage, :address, :purchase_price, :acquired_on, :sold_on)
  end
end
