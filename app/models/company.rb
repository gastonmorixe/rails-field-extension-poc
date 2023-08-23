# frozen_string_literal: true

# Company model
class Company < ApplicationRecord
  field :id, ID
  field :name, String
  field :phone, Int
  field :created_at, ISO8601DateTime
  field :updated_at, ISO8601DateTime

  has_many :employments
  has_many :employees, through: :employments, source: :user
end
