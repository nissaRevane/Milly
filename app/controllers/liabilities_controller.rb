class LiabilitiesController < ApplicationController
  before_action :set_liability, only: [:show, :edit, :update, :destroy]
  # The form partial offers the property select, and it is also re-rendered on failure.
  before_action :set_properties, only: [:new, :create, :edit, :update]

  def index
    @liability_type_filter = params[:liability_type].presence_in(Liability.liability_types.keys)
    @liabilities = current_user.liabilities.order(:liability_type, :risk_level, :name)
    @liabilities = @liabilities.where(liability_type: @liability_type_filter) if @liability_type_filter
  end

  def show
  end

  def new
    @liability = current_user.liabilities.build
  end

  def create
    @liability = current_user.liabilities.build(liability_params)
    if @liability.save
      redirect_to liabilities_path, notice: t("flash.liabilities.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @liability.update(liability_params)
      redirect_to liabilities_path, notice: t("flash.liabilities.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @liability.destroy
    redirect_to liabilities_path, notice: t("flash.liabilities.destroyed"), status: :see_other
  end

  private

  def set_liability
    @liability = current_user.liabilities.find(params[:id])
  end

  def set_properties
    @properties = current_user.properties.order(:usage, :name)
  end

  def liability_params
    scope_property_id(
      params.require(:liability).permit(
        :name, :risk_level, :liability_type, :ownership_share, :property_id,
        :started_on, :ended_on,
        *Liability::AMORTIZATION_FIELDS
      )
    )
  end
end
