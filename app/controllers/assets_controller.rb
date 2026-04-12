class AssetsController < ApplicationController
  before_action :set_asset, only: [:edit, :update, :destroy]

  def index
    @assets = current_user.assets.order(:risk_level, :name)
  end

  def new
    @asset = current_user.assets.build
  end

  def create
    @asset = current_user.assets.build(asset_params)
    if @asset.save
      redirect_to assets_path, notice: t("flash.assets.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @asset.update(asset_params)
      redirect_to assets_path, notice: t("flash.assets.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @asset.destroy
    redirect_to assets_path, notice: t("flash.assets.destroyed"), status: :see_other
  end

  private

  def set_asset
    @asset = current_user.assets.find(params[:id])
  end

  def asset_params
    params.require(:asset).permit(:name, :risk_level)
  end
end
