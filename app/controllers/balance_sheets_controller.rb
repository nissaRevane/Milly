class BalanceSheetsController < ApplicationController
  SUMMARY_TABS = %w[general real_estate dashboard].freeze

  before_action :set_balance_sheet, only: [:show, :edit, :update, :destroy, :summary]

  def index
    @balance_sheets = current_user.balance_sheets.order(closing_date: :desc)
  end

  def show
    @assets_by_category = @balance_sheet.assets_by_category
    @liabilities_by_category = @balance_sheet.liabilities_by_category

    # Navigation only: the header steps to the neighbouring bilans. Either is nil at the
    # ends of the série, and the arrow on that side renders disabled.
    @previous = @balance_sheet.previous
    @following = @balance_sheet.following
  end

  def new
    @source = source_balance_sheet
    @balance_sheet = current_user.balance_sheets.build(closing_date: Date.today)
  end

  def create
    @source = source_balance_sheet
    @balance_sheet = current_user.balance_sheets.build(balance_sheet_params)

    if save_with_copied_lines
      redirect_to @balance_sheet, notice: creation_notice
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
    case @tab
    when "real_estate"
      @property_positions = @balance_sheet.real_estate_positions
      @real_estate_usage_totals = @balance_sheet.real_estate_totals_by_usage(@property_positions)
      @real_estate_variation = @previous && @balance_sheet.real_estate_variation_against(@previous, @property_positions)
    when "dashboard"
      # Les mêmes regroupements que la synthèse, lus en graphiques plutôt qu'en tableaux :
      # l'onglet ne calcule rien de neuf, il donne une autre forme aux mêmes chiffres. Les
      # positions immobilières viennent en plus, une barre par bien.
      #
      # Les anneaux sont découpés sur les catégories du tableau de bord — mêmes regroupements,
      # mêmes clés, donc mêmes couleurs (voir BreakdownCategory) : une teinte doit
      # nommer le même poste d'un écran à l'autre. Le miroir d'accueil lit l'historique entier,
      # l'anneau ne lit qu'un bilan, d'où la série d'un seul élément.
      @assets_breakdown = BalanceSheet.assets_breakdown_for([@balance_sheet])
      @liabilities_breakdown = BalanceSheet.liabilities_breakdown_for([@balance_sheet])
      @property_positions = @balance_sheet.real_estate_positions
      @variations = @previous && @balance_sheet.variations_against(@previous)

      # Le cœur des anneaux dit d'où viennent leurs totaux : le bilan précédent, puis celui
      # d'il y a un an. Les deux se lisent sur les mêmes variations — un même écart ne peut
      # donc pas s'écrire d'une façon au centre d'un anneau et d'une autre sur une tuile.
      @year_ago = @balance_sheet.year_ago
      @yearly_variations = @year_ago && @balance_sheet.variations_against(@year_ago)
    else
      @assets_by_category = @balance_sheet.assets_by_category
      @liabilities_by_category = @balance_sheet.liabilities_by_category
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

  # Le bilan et les lignes qu'il reprend de sa source tiennent dans UNE transaction : la copie
  # échouant à mi-chemin, c'est un bilan vide qui restait en base — celui-là même que
  # l'utilisateur venait de demander plein.
  #
  # Renvoie nil quand le bilan lui-même est refusé (date déjà prise), ce qui suffit à la
  # branche 422 : rien n'a alors été écrit, et l'objet n'a pas d'id à traîner dans le
  # formulaire réaffiché.
  def save_with_copied_lines
    BalanceSheet.transaction do
      raise ActiveRecord::Rollback unless @balance_sheet.save

      @skipped_lines = @source ? @balance_sheet.copy_lines_from(@source) : 0
      true
    end
  end

  # Une duplication qui a écarté des lignes le dit : celles dont l'actif ou la dette n'existe
  # pas à la nouvelle date de clôture ne sont pas recopiées (voir BalanceSheet#copy_lines_from),
  # et un bilan revenu plus court qu'attendu sans un mot ressemble à une duplication ratée.
  def creation_notice
    return t("flash.balance_sheets.created") if @source.nil?
    return t("flash.balance_sheets.duplicated") if @skipped_lines.zero?

    t("flash.balance_sheets.duplicated_partial", count: @skipped_lines)
  end

  def balance_sheet_params
    params.require(:balance_sheet).permit(:closing_date)
  end
end
