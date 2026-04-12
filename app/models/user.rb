class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :assets, dependent: :destroy
  has_many :liabilities, dependent: :destroy
  has_many :balance_sheets, dependent: :destroy

  validates :firstname, presence: true
  validates :lastname, presence: true

  def full_name
    "#{firstname} #{lastname}"
  end
end
