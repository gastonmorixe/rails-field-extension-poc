require 'dry-struct'

module Types
  include Dry.Types()
end

class BaseStruct < Dry::Struct
  # Symbolize input keys
  #
  # @example
  #   User.new('name' => 'Jane')
  #   => #<User name="Jane">
  transform_keys(&:to_sym)

  # Tolerance to extra keys
  # Structs ignore extra keys by default. This can be changed by replacing the constructor.
  schema schema.strict
end

class Card < BaseStruct
  attribute :number, Types::String
  attribute :cvv, Types::String
end

class User < BaseStruct
  attribute :id, Types::Integer
  attribute :name, Types::String

  # Default values
  attribute :admin, Types::Bool.default(false)

  # Nested hash
  attribute? :address do
    attribute :address_line_1, Types::String
    attribute :address_line_2, Types::String
  end # TODO how to make nested hash optional?

  # optional attribute strict: it's optional but requires to be set as nil if unused when instance created .new
  attribute :email, Types::String.optional

  # Tolerance to missing keys
  # You can mark certain keys as optional by calling attribute?.
  #
  # optional attribute strict: doesn't need to be present or set as nil when instance created .new
  attribute? :age, Types::Integer

  # Compositing Structs
  attribute :card, Card
end

user = User.new(id: 2, name: 'Gaston', email: 'gaston@example.com', address: { address_line_1: "hola", address_line_2: "pepe" }, card: { number: "1234", cvv: "421" })
puts user.inspect

puts User.schema.inspect

# irb> User.schema
# => #<Dry::Types[Constructor<Schema<key_fn=.to_sym strict keys={id: Constrained<Nominal<Integer> rule=[type?(Integer)]> name: Constrained<Nominal<String> rule=[type?(String)]> admin: Default<Sum<Constrained<Nominal<TrueClass> rule=[type?(TrueClass)]> | Constrained<Nominal<FalseClass> rule=[type?(FalseClass)]>> value=false> address?: User::Address email: Sum<Constrained<Nominal<NilClass> rule=[type?(NilClass)]> | Constrained<Nominal<String> rule=[type?(String)]>> age?: Constrained<Nominal<Integer> rule=[type?(Integer)]>}> fn=Kernel.Hash>]>

# note: it errors if address is set to nil or anything does doesn't comply the interface of both attributes declared. 
# not setting address is ok, but seeting nil or wrong contract is not.

# irb> user = User.new(id: 2, name: 'Gaston', email: 'gaston@example.com', address: { address_line_1: "hola", address_line_2: "pepe" })
# => #<User id=2 name="Gaston" admin=false address=#<User::Address address_line_1="hola" address_line_2="pepe"> email="gaston@example.com" age=nil>
