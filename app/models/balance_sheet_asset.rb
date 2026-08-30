class BalanceSheetAsset < ApplicationRecord
  belongs_to :balance_sheet
  belongs_to :asset

  # Le montant détenu, tel que SQL le calcule. En constante parce que deux lectures s'en
  # servent — le total d'un bilan (BalanceSheet#total_assets) et la série chronologique de
  # tous les bilans (BalanceSheet.timeline_for) — et qu'un arrondi qui divergerait entre
  # les deux ferait dire deux montants différents au même bilan selon la page qui le lit.
  # L'arrondi de la quote-part avant la multiplication n'est pas décoratif : voir
  # BalanceSheet#total_assets.
  OWNED_VALUE_SQL = "ROUND(balance_sheet_assets.value * ROUND(assets.ownership_share / 100, 4), 2)".freeze

  validates :value, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :asset_id, uniqueness: { scope: :balance_sheet_id }

  # Un actif n'entre pas dans un bilan clos hors de sa période de détention. Le formulaire
  # ne le propose déjà plus (BalanceSheetAssetsController#set_available_assets) ; ceci en
  # est le filet côté modèle. À la création seulement : une ligne enregistrée est de
  # l'histoire, et une période resserrée après coup sur l'actif ne doit pas la rendre
  # immodifiable.
  validate :asset_within_its_lifespan, on: :create

  # Une ligne ne traverse jamais deux comptes. asset_id arrive d'un formulaire, et un id
  # forgé désignant l'actif d'un autre utilisateur satisfait la clé étrangère : le bilan
  # afficherait alors le nom, la catégorie et le bien de cet inconnu. Le contrôleur ne
  # propose déjà que les actifs de l'utilisateur (#set_available_assets), mais il ne fait
  # que remplir un select — ceci en est le filet côté modèle, exactement comme
  # PropertyLinkable#property_belongs_to_owner pour le rattachement à un bien.
  #
  # Sur toutes les validations et pas seulement à la création : réaffecter une ligne
  # existante passe par le même paramètre.
  validate :asset_belongs_to_the_same_account

  def owned_value
    (value * asset.share_ratio).round(2)
  end

  # La catégorie d'une ligne est celle de l'actif qu'elle chiffre : c'est par elle que le bilan
  # groupe ses lignes (voir BalanceSheet#assets_by_category).
  delegate :category_key, to: :asset

  private

  def asset_belongs_to_the_same_account
    return if asset.nil? || balance_sheet.nil?
    return if asset.user_id == balance_sheet.user_id

    errors.add(:asset, :invalid)
  end

  def asset_within_its_lifespan
    return if asset.nil? || balance_sheet.nil?
    return if asset.available_on?(balance_sheet.closing_date)

    errors.add(:asset, :outside_lifespan)
  end
end
