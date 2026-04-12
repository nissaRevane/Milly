class LiabilitiesController < ApplicationController
  before_action :set_liability, only: [:edit, :update, :destroy]

  def index
    @liabilities = current_user.liabilities.order(:risk_level, :name)
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

  def liability_params
    params.require(:liability).permit(:name, :risk_level)
  end
end
