# frozen_string_literal: true

# Provides enforcement of declared field for ActiveRecord models.
module FieldEnforcement
  module Utils
    class << self
      GQL_TO_RAILS_TYPE_MAP = {
        GraphQL::Types::String => :string,
        ::GraphQL::Types::Int => :integer,
        ::GraphQL::Types::Float => :float,
        ::GraphQL::Types::Boolean => :boolean,
        ::GraphQL::Types::ID => :integer, # or :string depending on how you handle IDs
        ::GraphQL::Types::ISO8601DateTime => :datetime,
        ::GraphQL::Types::ISO8601Date => :date,
        ::GraphQL::Types::JSON => :json,
        ::GraphQL::Types::BigInt => :bigint
      }

      def generate_migration_code(obj, field_name, field_type)
        obj_class = obj.class
        class_name = obj_class.name
        table_name = obj_class.table_name # class_name.tableize

        field_type_for_db = GQL_TO_RAILS_TYPE_MAP[field_type]
        if field_type_for_db.nil?
          raise "Declared field (#{field_name}) of type (#{field_type}) in class #{class_name} missing type mapping"
        end

        migration_class_name = "Add#{field_name.to_s.camelize}To#{class_name}"
        migration_filename = "#{Time.now.utc.strftime('%Y%m%d%H%M%S')}_#{migration_class_name.underscore}.rb"
        migration_code = <<-MIGRATION
class #{migration_class_name} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]
  def change
    add_column :#{table_name}, :#{field_name}, :#{field_type_for_db}
  end
end
MIGRATION

        [migration_filename, migration_code]
      end
    end
  end

  # Declares an field with enforcement
  # @param name [Symbol, String] the name of the field
  # @param type [Symbol, String, Class] the type of the filed
  # @return [void]
  # @!macro [attach] field
  #   @attribute $1
  #   @return [$2]
  def field(name, type)
    # Check if type is a valid GraphQL type
    # GraphQL::Types.const_get(type) if type.is_a?(Symbol) || type.is_a?(String)

    declared_fields << OpenStruct.new(name: name.to_s, type:) # TODO: null:, default: etc
  end

  @@processed_classes = {}
  def processed_classes
    @@processed_classes
  end

  def gql_type
    return @@processed_classes[self] if @@processed_classes[self].present?

    # Assuming this returns the fields defined with your custom DSL
    fields = declared_fields
    owner_self = self

    gql_type = Class.new(::Types::BaseObject) do
      graphql_name "#{owner_self.name}Type"
      description "A type representing a #{owner_self.name}"

      fields.each do |f|
        next if f.type.nil? # TODO: ! remove references fields

        # Assuming a proper mapping from your custom types to GraphQL types
        field f.name, f.type
      end
    end

    # Cache the processed class here to prevent infinite recursion
    @@processed_classes[self] = gql_type

    gql_type.class_eval do
      owner_self.reflections.each do |association_name, reflection|
        if reflection.macro == :has_many

          reflection_klass = if reflection.options[:through]
                               through_reflection_klass = reflection.through_reflection.klass
                               source_reflection_name = reflection.source_reflection_name.to_s
                               source_reflection = through_reflection_klass.reflections[source_reflection_name]
                               source_reflection ? source_reflection.klass : through_reflection_klass
                             else
                               reflection.klass
                             end

          field association_name, [reflection_klass.gql_type], null: true
        elsif reflection.macro == :belongs_to
          field association_name, reflection.klass.gql_type, null: true
        end
      end
    end

    gql_type
  end

  class << self
    def extended(base)
      class << base
        def declared_fields
          @_declared_fields ||= []
        end

        def declared_fields=(value)
          @_declared_fields = value
        end
      end

      base.class_eval do
        define_method :enforce_declared_fields do
          database_columns = self.class.column_names
          declared_fields_names = self.class.declared_fields.map(&:name)
          extra_fields = declared_fields_names - database_columns
          # Model may have extra fields that are not in the database schema
          # but are defined in the model. This is useful for computed fields.
          extra_fields = extra_fields.filter{ |f| !self.respond_to?(f) }
          associations_columns = self.class.reflections.values.map do |r|
            r.foreign_key
          end
          missing_fields = database_columns - declared_fields_names - associations_columns

          extra_fields.each do |field_name|
            # Generate the migration code for this field
            field = self.class.declared_fields.find { |df| df.name == field_name }
            migration_code = FieldEnforcement::Utils.generate_migration_code(self, field.name, field.type)

            error_message = "Declared field '#{field_name}' not found in db for model #{self.class.name}."
            puts "\n\n\n----------\n"
            puts error_message
            puts "This is what the migration should look like:\n\n"
            puts "# #{migration_code[0]}"
            puts migration_code[1]
            puts "----------\n\n\n"
            raise error_message
            # puts 'Do you want to generate it? [y/N]'

            # response = gets.chomp
            # if response.downcase == 'y'
            #   # TODO: create_migration_file(self.class.name, field, migration_code)
            #   puts "Migration created! Don't forget to run the migration."
            # else
            #   puts 'Migration was not created.'
            # end
          end

          unless missing_fields.empty?
            raise "fields must be declared in #{self.class.name}: #{missing_fields.join(', ')}"
          end
        end
      end

      base.after_initialize :enforce_declared_fields
    end
  end
end

# irb(main):005:0> ls GraphQL::Types
# constants: BigInt  Boolean  Float  ID  ISO8601Date  ISO8601DateTime  Int  JSON  Relay  String
# => nil

# TODOs:
# TODO: mapper or dry-type / dry-struct
# https://github.com/rmosolgo/graphql-ruby/blob/master/lib/graphql/schema/member/build_type.rb#L12
# https://github.com/rmosolgo/graphql-ruby/blob/master/lib/graphql/types/iso_8601_date_time.rb
# https://github.com/rmosolgo/graphql-ruby/blob/master/spec/integration/rails/generators/graphql/object_generator_spec.rb#L6
# https://github.com/rmosolgo/graphql-ruby/blob/master/lib/graphql/schema/field.rb#L589
