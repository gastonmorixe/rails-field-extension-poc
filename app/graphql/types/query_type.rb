module Types
  class QueryType < Types::BaseObject
    include GraphQL::Types::Relay::HasNodeField
    include GraphQL::Types::Relay::HasNodesField

    # Fields
    field :companies, [::Company.gql_type], null: true
    field :company, ::Company.gql_type, null: true do
      argument :id, ID, required: true
    end

    field :users, [::User.gql_type], null: true
    field :user, ::User.gql_type, null: true do
      argument :id, ID, required: true
    end

    field :todos, [::Todo.gql_type], null: true
    field :todo, ::Todo.gql_type, null: true do
      argument :id, ID, required: true
    end

    field :employments, [::Employment.gql_type], null: true

    # Resolvers
    def companies
      Company.all
    end

    def company(id:)
      Company.where(id:).last
    end

    def users
      User.all
    end

    def user(id:)
      User.where(id:).last
    end

    def todos
      Todo.all
    end

    def todo(id:)
      Todo.where(id:).last
    end

    def employments
      Employment.all
    end
  end
end
