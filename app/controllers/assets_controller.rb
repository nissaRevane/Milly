class AssetsController < ApplicationController
  before_action :set_asset, only: [:edit, :update, :destroy]
  before_action :refuse_reserved_asset_type, only: [:create]

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
    # The actif of a bien is deleted with the bien, never on its own: the user could not
    # recreate it from here, since "Immobilier" is not a type the form offers.
    if @asset.owned_by_property?
      redirect_to assets_path, alert: t("flash.assets.property_owned"), status: :see_other
      return
    end

    @asset.destroy
    redirect_to assets_path, notice: t("flash.assets.destroyed"), status: :see_other
  end

  private

  def set_asset
    @asset = current_user.assets.find(params[:id])
  end

  # A forged "Immobilier" is refused outright rather than silently saved as another type:
  # that type is minted by creating a bien, and by nothing else.
  def refuse_reserved_asset_type
    return unless params.dig(:asset, :asset_type) == Asset::RESERVED_ASSET_TYPE

    @asset = current_user.assets.build(asset_params.except(:asset_type))
    @asset.errors.add(:asset_type, :reserved_for_property)
    render :new, status: :unprocessable_entity
  end

  def asset_params
    params.require(:asset).permit(*permitted_asset_attributes)
  end

  # Le rattachement à un bien ne se saisit jamais ici : seul l'actif immobilier se rattache
  # à un bien (voir PropertyLinkable), et c'est le bien qui le crée et qui le rattache.
  #
  # The bien owns the type and the rattachement of its actif, and its name too. What is
  # left to edit here are the numbers and the dates. An orphan actif — one whose bien has
  # been deleted since — keeps its name editable, as nothing else can name it anymore.
  #
  # Les dates restent modifiables même pour l'actif d'un bien : la période du bien n'est
  # qu'un défaut (voir Lifespanable).
  def permitted_asset_attributes
    lifespan = [:started_on, :ended_on]
    return [:name, :risk_level, :asset_type, :ownership_share, *lifespan] unless @asset&.real_estate?

    editable_name = @asset.owned_by_property? ? [] : [:name]
    [*editable_name, :risk_level, :ownership_share, *lifespan]
  end
end
