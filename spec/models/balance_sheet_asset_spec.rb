require "rails_helper"

RSpec.describe BalanceSheetAsset, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:balance_sheet) }
    it { is_expected.to belong_to(:asset) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:value) }
    it { is_expected.to validate_numericality_of(:value).is_greater_than_or_equal_to(0) }

    # Le formulaire ne propose déjà plus l'actif hors période ; ceci est le filet côté modèle.
    it "rejects an asset that did not exist yet at the closing date" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 3, 31))
      asset = create(:asset, user: bs.user, started_on: Date.new(2025, 5, 1))
      line = build(:balance_sheet_asset, balance_sheet: bs, asset: asset)

      expect(line).not_to be_valid
      expect(line.errors[:asset]).to eq(["n'existait pas à la date de ce bilan"])
    end

    it "rejects an asset already gone at the closing date" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 3, 31))
      asset = create(:asset, user: bs.user, ended_on: Date.new(2025, 2, 1))

      expect(build(:balance_sheet_asset, balance_sheet: bs, asset: asset)).not_to be_valid
    end

    it "accepts an asset that entered anywhere in the month of the closing date" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 3, 1))
      asset = create(:asset, user: bs.user, started_on: Date.new(2025, 3, 28))

      expect(build(:balance_sheet_asset, balance_sheet: bs, asset: asset)).to be_valid
    end

    # Une ligne enregistrée est de l'histoire : resserrer la période de l'actif après coup
    # ne doit pas empêcher de corriger son montant.
    it "keeps an existing line editable after the asset lifespan moved" do
      bs = create(:balance_sheet, closing_date: Date.new(2025, 3, 31))
      asset = create(:asset, user: bs.user)
      line = create(:balance_sheet_asset, balance_sheet: bs, asset: asset)

      asset.update!(started_on: Date.new(2025, 5, 1))

      expect(line.reload.update(value: 42)).to be true
    end

    it "validates uniqueness of asset_id scoped to balance_sheet" do
      bs = create(:balance_sheet)
      asset = create(:asset, user: bs.user)
      create(:balance_sheet_asset, balance_sheet: bs, asset: asset)
      duplicate = build(:balance_sheet_asset, balance_sheet: bs, asset: asset)
      expect(duplicate).not_to be_valid
    end
  end

  describe "#owned_value" do
    let(:bs) { create(:balance_sheet) }

    it "returns the full value when the asset is fully owned" do
      asset = create(:asset, user: bs.user, ownership_share: 100)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 10_000)

      expect(bsa.owned_value).to eq(10_000)
    end

    it "returns half the value when the asset is owned at 50%" do
      asset = create(:asset, user: bs.user, ownership_share: 50)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 10_000)

      expect(bsa.owned_value).to eq(5_000)
    end

    it "rounds the owned value to two decimals" do
      asset = create(:asset, user: bs.user, ownership_share: 33.33)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset, value: 1_001.55)

      expect(bsa.owned_value).to eq(BigDecimal("333.82"))
    end
  end

  describe "la fiscalité latente" do
    let(:bs) { create(:balance_sheet) }

    def pea(share: 100, rate: 18.6)
      create(:asset, user: bs.user, asset_type: :financial_investment,
                     ownership_share: share, tax_rate: rate)
    end

    it "taxes the plus-value at the taux de sortie of the asset" do
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: pea,
                                         value: 45_000, invested_value: 32_000)

      expect(bsa.gross_owned_value).to eq(45_000)
      expect(bsa.owned_invested_value).to eq(32_000)
      expect(bsa.capital_gain).to eq(13_000)
      expect(bsa.latent_tax).to eq(BigDecimal("2418"))
      expect(bsa.owned_value).to eq(BigDecimal("42582"))
    end

    it "applies the quote-part to the base as well as to the value" do
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: pea(share: 50),
                                         value: 45_000, invested_value: 32_000)

      expect(bsa.owned_invested_value).to eq(16_000)
      expect(bsa.capital_gain).to eq(6_500)
      expect(bsa.latent_tax).to eq(BigDecimal("1209"))
      expect(bsa.owned_value).to eq(BigDecimal("21291"))
    end

    it "taxes nothing while the base imposable is unknown" do
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: pea, value: 45_000)

      expect(bsa.owned_invested_value).to be_nil
      expect(bsa.capital_gain).to be_zero
      expect(bsa.latent_tax).to be_zero
      expect(bsa.owned_value).to eq(bsa.gross_owned_value)
    end

    # Une moins-value ne donne aucun crédit d'impôt : elle ne fait pas remonter la valeur.
    it "taxes nothing on a moins-value" do
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: pea,
                                         value: 28_000, invested_value: 32_000)

      expect(bsa.latent_tax).to be_zero
      expect(bsa.owned_value).to eq(28_000)
    end

    # Les quatre montants de la note d'une ligne s'additionnent sous les yeux du lecteur :
    # investi + plus-value = valeur détenue, et plus-value × taux = impôt. Sur une quote-part
    # tordue aussi, sans quoi la phrase demanderait de croire une arithmétique fausse.
    it "keeps the displayed amounts consistent on an awkward quote-part" do
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: pea(share: 33.33, rate: 17.2),
                                         value: 1_001.55, invested_value: 333.17)

      expect(bsa.owned_invested_value + bsa.capital_gain).to eq(bsa.gross_owned_value)
      expect((bsa.capital_gain * BigDecimal("0.172")).round(2)).to eq(bsa.latent_tax)
    end

    it "taxes nothing on an asset carrying no taux" do
      asset = create(:asset, user: bs.user, asset_type: :savings_account)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: asset,
                                         value: 45_000, invested_value: 32_000)

      expect(bsa.latent_tax).to be_zero
    end

    # Ruby et SQL doivent tomber sur le même centime : le total d'un bilan agrège
    # LATENT_TAX_SQL quand la ligne calcule #latent_tax (voir la constante). Balayé sur des
    # quote-parts et des taux qui ne tombent pas rond, là où un arrondi divergent se voit.
    it "agrees with the SQL aggregate down to the cent" do
      [[33.33, 17.2, 1_001.55, 333.17], [50, 18.6, 45_000, 32_000], [66.67, 30, 7_777.77, 1_234.56],
       [12.5, 7.5, 999_999.99, 0.01], [100, 18.6, 45_000.05, 44_999.99]].each do |share, rate, value, invested|
        create(:balance_sheet_asset, balance_sheet: bs, asset: pea(share: share, rate: rate),
                                     value: value, invested_value: invested)
      end

      expect(bs.total_assets).to eq(bs.balance_sheet_assets.sum(&:owned_value))
    end

    # Le total d'un bilan doit rester la somme de ce que ses lignes affichent, sans quoi le
    # bilan dirait un montant et sa ventilation un autre.
    it "keeps the total reconcilable line by line" do
      create(:balance_sheet_asset, balance_sheet: bs, asset: pea(share: 33.33), value: 1_001.55,
                                   invested_value: 333.17)
      create(:balance_sheet_asset, balance_sheet: bs, asset: pea(share: 50, rate: 30),
                                   value: 7_777.77, invested_value: 1_234.56)
      lines = bs.balance_sheet_assets

      expect(bs.total_assets).to eq(lines.sum(&:owned_value))
      expect(bs.total_assets).to eq(lines.sum(&:gross_owned_value) - lines.sum(&:latent_tax))
    end

    # Le formulaire d'une ligne désactive son champ quand l'actif choisi n'est pas imposé :
    # le paramètre n'arrive donc pas, et sans ce filet l'ancienne base resterait collée.
    it "drops the base imposable when the line moves to a non-taxable asset" do
      livret = create(:asset, user: bs.user, asset_type: :savings_account)
      bsa = create(:balance_sheet_asset, balance_sheet: bs, asset: pea,
                                         value: 45_000, invested_value: 32_000)

      bsa.update!(asset: livret)

      expect(bsa.reload.invested_value).to be_nil
    end

    it "refuses a negative base imposable" do
      bsa = build(:balance_sheet_asset, balance_sheet: bs, asset: pea, invested_value: -1)

      expect(bsa).not_to be_valid
    end
  end
end
