class Todo < ApplicationRecord
  field :id, :integer
  field :created_at, :datetime
  field :updated_at, :datetime
  field :content, :string
  field :completed_at, :datetime

  belongs_to :user
end
