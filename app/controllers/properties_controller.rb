class PropertiesController < ApplicationController
  before_action :set_property, only: [:edit, :update, :destroy]

  def index
    @properties = current_user.properties.order(:usage, :name)
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

  def property_params
    params.require(:property).permit(:name, :usage)
  end
end
