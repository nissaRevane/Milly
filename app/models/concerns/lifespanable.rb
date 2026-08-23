# Une ligne, actif ou dette, qui n'existe qu'entre deux dates, l'une et l'autre facultatives :
# sans borne de début elle a toujours existé, sans borne de fin elle existe encore. Un bilan
# ne se voit proposer que les lignes qui existaient à sa date de clôture — voir
# BalanceSheetAssetsController#set_available_assets.
#
# La comparaison se fait au mois, jamais au jour : un bien acheté le 20 août entre dans le
# bilan clos le 1er août comme dans celui clos le 31, et un prêt soldé le 3 septembre
# figure encore dans le bilan clos le 30 septembre. C'est la tolérance du mois en cours :
# un patrimoine se photographie à la fin d'un mois, et écarter une ligne pour quelques
# jours d'écart à l'intérieur du mois où elle entre ou sort ne dirait rien de juste.
module Lifespanable
  extend ActiveSupport::Concern

  included do
    # Les lignes qu'un bilan clos à +date+ peut porter. Le pendant SQL de #available_on?,
    # en constante nulle part parce que les deux formes ne peuvent pas se partager : celle-ci
    # doit filtrer en base pour ne pas charger tout le compte à chaque formulaire.
    scope :available_on, lambda { |date|
      where("started_on IS NULL OR started_on <= :last_day", last_day: date.end_of_month)
        .where("ended_on IS NULL OR ended_on >= :first_day", first_day: date.beginning_of_month)
    }

    validate :ended_on_after_started_on

    # Rattacher une ligne à un bien lui donne la période du bien : un actif ou une dette
    # adossés à un immeuble naissent avec l'achat et meurent avec la vente. Ce n'est qu'un défaut,
    # posé à la création et sur les bornes laissées vides — un compte courant ouvert deux ans
    # après l'achat garde la date que l'utilisateur y écrit. Property propage ensuite ses
    # propres changements de dates aux bornes restées d'origine (voir Property).
    before_validation :adopt_property_lifespan, on: :create, if: :property
  end

  # La ligne existait-elle dans le mois où +date+ tombe ?
  def available_on?(date)
    (started_on.nil? || started_on <= date.end_of_month) &&
      (ended_on.nil? || ended_on >= date.beginning_of_month)
  end

  private

  def adopt_property_lifespan
    self.started_on = property.acquired_on if started_on.nil?
    self.ended_on = property.sold_on if ended_on.nil?
  end

  def ended_on_after_started_on
    return if started_on.nil? || ended_on.nil? || ended_on >= started_on

    errors.add(:ended_on, :ended_before_started)
  end
end
