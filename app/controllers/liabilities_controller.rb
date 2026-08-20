class LiabilitiesController < ApplicationController
  # Les facettes de la fiche, dans l'ordre des onglets. « general » est celle qu'on obtient
  # sans ?tab= : c'est le passif lui-même, et c'est là qu'on revient d'un onglet disparu.
  TABS = %w[general history schedule].freeze
  DEFAULT_TAB = "general".freeze

  before_action :set_liability, only: [:show, :update, :destroy]
  # Le select de rattachement est offert par le formulaire de création comme par la fiche,
  # et le formulaire est aussi réaffiché en cas d'échec.
  before_action :set_properties, only: [:new, :create, :show, :update]

  def index
    # Voir AssetsController#index : la liste se range par grande catégorie, le filtre aussi.
    @category_filter = params[:category].presence_in(BreakdownCategory.family_keys(BreakdownCategory::LIABILITIES))
    liabilities = current_user.liabilities
    if @category_filter
      liabilities = liabilities.where(
        liability_type: BreakdownCategory.types_for(BreakdownCategory::LIABILITIES, @category_filter)
      )
    end
    @liabilities = liabilities.ordered_by_category
  end

  # La fiche : elle est aussi le formulaire du passif, chaque champ s'y corrigeant sur place.
  def show
    load_tab
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

  # Un enregistrement ne renvoie pas à la liste mais à la fiche, sur l'onglet où l'on était :
  # on corrige un champ pour continuer à lire le passif, pas pour le quitter. Un refus
  # réaffiche cette même fiche, ses erreurs en tête et la valeur refusée dans son champ.
  def update
    if @liability.update(liability_params)
      redirect_to fiche_path, notice: t("flash.liabilities.updated")
    else
      load_tab
      render :show, status: :unprocessable_entity
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

  # L'onglet demandé, ramené à la fiche quand il n'existe pas — ou plus : un passif qui quitte
  # les types amortissables perd son échéancier, et l'enregistrement doit alors renvoyer vers
  # un onglet qui est toujours là.
  def current_tab
    tab = TABS.include?(params[:tab]) ? params[:tab] : DEFAULT_TAB
    return DEFAULT_TAB if tab == "schedule" && !@liability.amortizable_type?

    tab
  end

  # Chaque onglet est une page entière rendue par le serveur : on ne lit que ce qu'il montre
  # (voir BalanceSheetsController#summary).
  def load_tab
    @tab = current_tab
    @history = @liability.value_history if @tab == "history"
  end

  # La fiche telle qu'on y revient : sur l'onglet où l'on était, et sans ?tab= sur celui
  # d'accueil — l'adresse d'une fiche reste celle qu'on partage.
  def fiche_path
    tab = current_tab

    liability_path(@liability, tab: (tab unless tab == DEFAULT_TAB))
  end

  def liability_params
    drop_property_link_unless_linkable(
      scope_property_id(
        params.require(:liability).permit(
          :name, :liability_type, :ownership_share, :property_id,
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
