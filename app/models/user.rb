# frozen_string_literal: true

# User model
class User < ApplicationRecord
  field :id, :integer
  field :name, :string
  field :age, :integer
  field :zipcode, :integer
  field :notes, :string
  field :created_at, :datetime
  field :updated_at, :datetime

  has_many :employments
  has_many :companies, through: :employments
end
