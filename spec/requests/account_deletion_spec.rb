require "rails_helper"

# Le droit à l'effacement : héberger le patrimoine de quelqu'un oblige à lui laisser le
# moyen de tout retirer lui-même, et à ne rien garder derrière.
RSpec.describe "Account deletion", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "offers the deletion from the account page" do
    get account_path

    expect(response.body).to include(I18n.t("views.account.show.delete"))
  end

  it "takes the account and everything it carried" do
    property = create(:property, user: user)
    create(:asset, user: user)
    create(:liability, user: user)
    sheet = create(:balance_sheet, user: user)
    create(:balance_sheet_asset, balance_sheet: sheet, asset: create(:asset, user: user))

    delete user_registration_path

    expect(User.exists?(user.id)).to be(false)
    expect(Property.exists?(property.id)).to be(false)
    expect(Asset.where(user_id: user.id)).to be_empty
    expect(Liability.where(user_id: user.id)).to be_empty
    expect(BalanceSheet.exists?(sheet.id)).to be(false)
    expect(BalanceSheetAsset.where(balance_sheet_id: sheet.id)).to be_empty
  end
end
