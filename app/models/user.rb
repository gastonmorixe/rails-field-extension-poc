require "field_enforcement"

# User model
class User < ApplicationRecord
  field :id, :integer
  field :name, :string
  field :nickname, :string
  field :age, :integer
  field :address1, :string
  field :address2, :string
  field :zipcode, :integer
  field :country, :string
  field :notes, :string
  field :created_at, :datetime
  field :updated_at, :datetime
  field :is_admin, :boolean

  has_many :employments
  has_many :companies, through: :employments
end
