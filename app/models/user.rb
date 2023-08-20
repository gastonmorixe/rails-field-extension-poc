# frozen_string_literal: true

# User model
class User < ApplicationRecord
  field :id, ID
  field :name, String
  field :created_at, ISO8601DateTime
  field :updated_at, ISO8601DateTime

  has_many :employments
  has_many :companies, through: :employments
end
