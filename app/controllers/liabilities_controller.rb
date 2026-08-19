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
    drop_property_link_unless_linkable(
      scope_property_id(
        params.require(:liability).permit(
          :name, :risk_level, :liability_type, :ownership_share, :property_id,
          :started_on, :ended_on,
          *Liability::AMORTIZATION_FIELDS
        )
      )
    )
  end

  # Le rattachement suit le type : un crédit immobilier qui devient une dette court terme
  # perd son bien. Le formulaire masque déjà le champ pour les types qu'aucun bien ne porte,
  # donc il ne renvoie rien — et garder l'ancien rattachement ferait échouer la validation
  # du modèle sur un champ que l'utilisateur ne voit plus.
  def drop_property_link_unless_linkable(permitted)
    type = permitted[:liability_type] || (@liability || Liability.new).liability_type
    return permitted if Liability::PROPERTY_LINKABLE_TYPES.include?(type)

    permitted[:property_id] = nil
    permitted
  end
end
