# frozen_string_literal: true

# User model
class User < ApplicationRecord
  field :id, :id
  field :name, :string
  field :created_at, :datetime
  field :updated_at, :datetime

  has_many :employments
  has_many :companies, through: :employments
end
