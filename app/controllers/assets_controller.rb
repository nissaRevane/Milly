class AssetsController < ApplicationController
  before_action :set_asset, only: [:edit, :update, :destroy]
  # The form partial offers the property select, and it is also re-rendered on failure.
  before_action :set_properties, only: [:new, :create, :edit, :update]

  def index
    @asset_type_filter = params[:asset_type].presence_in(Asset.asset_types.keys)
    @assets = current_user.assets.order(:asset_type, :risk_level, :name)
    @assets = @assets.where(asset_type: @asset_type_filter) if @asset_type_filter
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

  def set_properties
    @properties = current_user.properties.order(:usage, :name)
  end

  def asset_params
    scope_property_id(
      params.require(:asset).permit(:name, :risk_level, :asset_type, :ownership_share, :property_id)
    )
  end
end
