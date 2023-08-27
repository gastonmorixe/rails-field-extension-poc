# User model
class User < ApplicationRecord
  field :id, :integer
  field :created_at, :datetime
  field :updated_at, :datetime
  field :name, :string
  field :nickname, :string
  field :age, :integer
  field :address1, :string
  field :address2, :string
  field :zipcode, :integer
  field :country, :string
  field :notes, :string
  field :is_admin, :boolean
  field :hi_user, :string

  has_many :employments
  has_many :companies, through: :employments
  has_many :todos

  def hi_user
    "hello #{name}"
  end
end
