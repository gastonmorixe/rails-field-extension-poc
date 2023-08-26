# frozen_string_literal: true

require 'logger'

# Provides enforcement of declared field for ActiveRecord models.
module FieldEnforcement
  module Utils
    LOGGER = begin
      logger = Logger.new($stdout)
      logger.level = Logger::INFO
      logger
    end

    class FieldEnforcementError < StandardError; end

    class FieldEnforcementMismatchError < FieldEnforcementError
      include ActiveSupport::ActionableError

      action 'Save migrations' do
        # models = FieldEnforcement::Utils.active_record_models
        # changes = models.map{ |m| FieldEnforcement::Utils.detect_changes(m) }
        # migrations = models.map{ |m| FieldEnforcement::Utils.generate_migration(m, changes, write: true) }
        # changes = FieldEnforcement::Utils.detect_changes(self)
        # debugger
        # TODO: save migrations idk how to pass the model it was called on
        raise 'TODO'
      end

      # action 'Run db:migrations' do
      #   ActiveRecord::Tasks::DatabaseTasks.migrate
      # end
    end

    class FieldEnforcementUnknownType < FieldEnforcementError; end

    # TODO: mapper can be different or custom
    GQL_TO_RAILS_TYPE_MAP = {
      ::GraphQL::Types::String => :string,
      ::GraphQL::Types::Int => :integer,
      ::GraphQL::Types::Float => :float,
      ::GraphQL::Types::Boolean => :boolean,
      ::GraphQL::Types::ID => :integer, # or :string depending on how you handle IDs
      ::GraphQL::Types::ISO8601DateTime => :datetime,
      ::GraphQL::Types::ISO8601Date => :date,
      ::GraphQL::Types::JSON => :json,
      ::GraphQL::Types::BigInt => :bigint
    }

    RAILS_TO_GQL_TYPE_MAP = {
      # id: ::GraphQL::Types::String,
      string: ::GraphQL::Types::String,
      integer: ::GraphQL::Types::Int,
      float: ::GraphQL::Types::Float,
      boolean: ::GraphQL::Types::Boolean,
      datetime: ::GraphQL::Types::ISO8601DateTime,
      date: ::GraphQL::Types::ISO8601Date,
      json: ::GraphQL::Types::JSON,
      bigint: ::GraphQL::Types::BigInt
    }

    class << self
      def allowed_types
        # TODO: this may depend on the current database adapter or mapper
        ActiveRecord::Base.connection.native_database_types.keys
      end

      def valid_type?(type)
        # TODO: this may depend on the current database adapter or mapper
        allowed_types.include?(type)
      end

      def active_record_models
        Rails.application.eager_load! # Ensure all models are loaded

        ActiveRecord::Base.descendants.reject do |model|
          !(model.is_a?(Class) && model < ApplicationRecord) ||
            model.abstract_class? ||
            model.name.nil? ||
            model.name == 'ActiveRecord::SchemaMigration'
        end
      end

      def detect_changes(model)
        previous_fields = model.attribute_types.map { |k, v| [k.to_sym, v.type] }.to_h
        declared_fields = model.declared_fields.map do |f|
          [f.name.to_sym, {
            name: f.type.to_sym,
            options: f.options
          }]
        end.to_h

        # puts "Log: previous_fields: #{previous_fields}"
        # puts "Log: declared_fields #{declared_fields}}"

        model_changes = {
          added: [],
          removed: [],
          renamed: [],
          type_changed: [],
          potential_renames: []
        }

        # Detect added and type-changed fields
        declared_fields.each do |name, type|
          type_name = type[:name]
          if previous_fields[name]
            if previous_fields[name] != type_name
              model_changes[:type_changed] << { name:, from: previous_fields[name], to: type }
            end
          else
            model_changes[:added] << { name:, type: }
          end
        end

        # Detect removed fields
        removed_fields = previous_fields.keys - declared_fields.keys
        model_changes[:removed] = removed_fields.map { |name| { name:, type: previous_fields[name] } }

        # Detect potential renames
        potential_renames = []
        model_changes[:removed].each do |removed_field|
          # puts "Log: removed_field: #{removed_field}"
          added_field = model_changes[:added].find { |f| f[:type] == removed_field[:type] }
          potential_renames << { from: removed_field[:name], to: added_field[:name] } if added_field
        end

        # puts "Log: potential_renames: #{potential_renames}"

        model_changes[:potential_renames] = potential_renames

        # Filter out incorrect renames (one-to-one mapping)
        potential_renames.each do |rename|
          next unless model_changes[:added].count { |f| f[:type] == rename[:to].to_sym } == 1 &&
                      model_changes[:removed].count { |f| f[:type] == rename[:from].to_sym } == 1

          model_changes[:renamed] << rename
          model_changes[:added].reject! { |f| f[:name] == rename[:to].to_sym }
          model_changes[:removed].reject! { |f| f[:name] == rename[:from].to_sym }
        end

        return model_changes unless model_changes.values.all?(&:empty?)

        nil
      end

      def generate_migration(model, model_changes, index: 0, write: false)
        model_name = model.name
        timestamp = Time.now.utc.strftime('%Y%m%d%H%M%S').to_i + index
        migration_class_name = "#{model_name}Migration#{timestamp}"

        migration_code = []
        migration_code << "class #{migration_class_name} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]"

        migration_code << '  def change'

        model_changes&.dig(:added)&.each do |change|
          field_type = change[:type]
          field_type_for_db = field_type[:name]
          # field_type_for_db = GQL_TO_RAILS_TYPE_MAP[field_type.constantize]
          # field_type_for_gql = RAILS_TO_GQL_TYPE_MAP[field_type.constantize]
          # TODO: ID should be string / integer? custom mapper
          migration_code << "    add_column :#{model_name.tableize}, :#{change[:name]}, :#{field_type_for_db}"
        end

        model_changes&.dig(:removed)&.each do |change|
          migration_code << "    remove_column :#{model_name.tableize}, :#{change[:name]}"
        end

        model_changes&.dig(:renamed)&.each do |change|
          change_to = change[:to]
          migration_code << "    rename_column :#{model_name.tableize}, :#{change[:from]}, :#{change_to}"
        end

        model_changes&.dig(:type_changed)&.each do |change|
          change_to = change[:to]
          migration_code << "    change_column :#{model_name.tableize}, :#{change[:name]}, :#{change_to}"
        end

        migration_code << '  end'
        migration_code << 'end'
        migration_code << ''

        # TODO: separate write migration to a method
        write_migration(migration_code, migration_class_name, timestamp) if write == true

        migration_code&.join("\n")
      end

      def write_migration(migration_code, migration_class_name, timestamp)
        migration_filename = "#{timestamp}_#{migration_class_name.underscore}.rb"
        migration_path = Rails.root.join('db', 'migrate', migration_filename)
        File.write(migration_path, migration_code.join("\n"))
        LOGGER.info "Migration saved at #{migration_path}"
        { migration_filename:, migration_path: }
      end
    end
  end

  def self.included(base)
    base.class_eval do
      class << base
        @@processed_classes = {}
        def processed_classes
          @@processed_classes
        end
      end
    end

    base.extend(ClassMethods)
    base.after_initialize do
      self.class.enforce_declared_fields
    end
  end

  module ClassMethods
    # TODO: Chceck all models at rails init app? like migrations?

    def declared_fields
      @declared_fields ||= []
    end

    def declared_fields=(value)
      @declared_fields = value
    end

    def write_migration
      changes = FieldEnforcement::Utils.detect_changes(self)
      FieldEnforcement::Utils.generate_migration(self, changes, write: true)
    end

    # Declares an field with enforcement
    # @param name [Symbol, String] the name of the field
    # @param type [Symbol, String] the type of the filed
    # @return [void]
    # @!macro [attach] field
    #   @attribute $1
    #   @return [$2]
    def field(name, type, **options)
      # Check if type is a valid GraphQL type
      # GraphQL::Types.const_get(type) if type.is_a?(Symbol) || type.is_a?(String)
      unless Utils.valid_type?(type)
        raise Utils::FieldEnforcementUnknownType,
              "Declared field '#{name}' in class '#{self.name}' of unknown type '#{type}'. Allowed types are: #{Utils.allowed_types.join(', ')}."
      end

      declared_fields << OpenStruct.new(name: name.to_s, type:, options:)
    end

    def gql_type
      return processed_classes[self] if processed_classes[self].present?

      fields = declared_fields
      owner_self = self

      type = Class.new(::Types::BaseObject) do
        graphql_name "#{owner_self.name}Type"
        description "A type representing a #{owner_self.name}"

        fields.each do |f|
          next if f.type.nil? # TODO: ! remove references fields

          # Assuming a proper mapping from your custom types to GraphQL types
          # TODO: use a better method or block
          field_gql_type = f.name == :id ? GraphQL::Types::ID : Utils::RAILS_TO_GQL_TYPE_MAP[f.type]
          field f.name, field_gql_type
        end
      end

      # Cache the processed class here to prevent infinite recursion
      processed_classes[self] = type

      type.instance_eval do
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

        type
      end
    end

    def enforce_declared_fields
      database_columns = column_names.map(&:to_sym)

      declared_fields_names = declared_fields.map(&:name)&.map(&:to_sym) || []

      changes = FieldEnforcement::Utils.detect_changes(self)
      # Utils::LOGGER.info "Detected changes: #{JSON.pretty_generate(changes)}"

      # previous_fields = changes[self.class.name][:previous_fields].keys
      # added_fields_names = changes&.dig(:added)&.map { |f| f && f[:name].to_sym } || []

      migration = FieldEnforcement::Utils.generate_migration(self, changes)

      # Extra fields that are not in the db but defined in the model
      # extra_fields = (declared_fields_names - added_fields_names).filter { |f| !respond_to?(f) }

      # associations_columns = self.class.reflections.values.map(&:foreign_key)

      # missing_fields = database_columns - declared_fields_names - associations_columns

      instance_methods = self.instance_methods(false).select do |method|
        instance_method(method).source_location.first.start_with?(Rails.root.to_s)
      end

      extra_methods = instance_methods - declared_fields_names.map(&:to_sym)
      # Utils::LOGGER.info "Detected extra_methods: #{extra_methods}"

      has_changes = !changes.nil?

      unless extra_methods.empty?
        # TODO: Custom error subclass
        raise "You have extra methods declared in #{name}: #{extra_methods.join(', ')}. Please remove them or declare them as fields."
      end

      return unless has_changes # missing_fields.empty? && extra_fields.empty?

      error_message = <<~STRING

----------------

Declared Fields:
#{declared_fields_names.join(', ')}


Database columns:
#{database_columns.join(', ')}


Changes:
#{changes}


Migration:
#{migration}

----------------

      STRING
      raise Utils::FieldEnforcementMismatchError, error_message
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

# irb(main):010:0> ActiveRecord::Base.connection.type_to_sql :string
# "varchar"
# irb(main):011:0> ActiveRecord::Base.connection.type_to_sql :bigint
# "bigint"
# irb(main):012:0> ActiveRecord::Base.connection.type_to_sql :int
# "int"

# irb(main):010:0> User.connection.schema_cache.instance_variable_get(:@columns_hash)
# {}

# irb(main):011:0> User.connection.schema_cache.columns_hash(User.table_name)
# {
#             "id" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3e158 @name="id", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3ff58 @sql_type="INTEGER", @type=:integer, @limit=nil, @precision=nil, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#           "name" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3dfc8 @name="name", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3e0b8 @sql_type="varchar", @type=:string, @limit=nil, @precision=nil, @scale=nil>, @null=true, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     "created_at" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3de88 @name="created_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3df78 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     "updated_at" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3dd48 @name="updated_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3df78 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>
# }

# irb(main):012:0> User.connection.schema_cache.instance_variable_get(:@columns_hash)
# {
#     "users" => {
#                 "id" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3e158 @name="id", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3ff58 @sql_type="INTEGER", @type=:integer, @limit=nil, @precision=nil, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#               "name" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3dfc8 @name="name", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3e0b8 @sql_type="varchar", @type=:string, @limit=nil, @precision=nil, @scale=nil>, @null=true, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#         "created_at" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3de88 @name="created_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3df78 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#         "updated_at" => #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3dd48 @name="updated_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3df78 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>
#     }
# }

# irb(main):015:0> User.attribute_types
# {
#             "id" => #<ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer:0x0000000120b3ffa8 @precision=nil, @scale=nil, @limit=nil, @range=-9223372036854775808...9223372036854775808>,
#           "name" => #<ActiveModel::Type::String:0x0000000120b3e108 @true="t", @false="f", @precision=nil, @scale=nil, @limit=nil>,
#     "created_at" => #<ActiveRecord::Type::DateTime:0x0000000117b5ef88 @precision=6, @scale=nil, @limit=nil>,
#     "updated_at" => #<ActiveRecord::Type::DateTime:0x0000000117b5ef88 @precision=6, @scale=nil, @limit=nil>
# }

# irb(main):028:0> User.connection.schema_cache.instance_variable_get(:@columns_hash)
# {}
# irb(main):029:0> User.connection.schema_cache.columns(User.table_name)
# [
#     [0] #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3e158 @name="id", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3ff58 @sql_type="INTEGER", @type=:integer, @limit=nil, @precision=nil, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [1] #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3dfc8 @name="name", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3e0b8 @sql_type="varchar", @type=:string, @limit=nil, @precision=nil, @scale=nil>, @null=true, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [2] #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3de88 @name="created_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3df78 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [3] #<ActiveRecord::ConnectionAdapters::Column:0x0000000120b3dd48 @name="updated_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000120b3df78 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>
# ]
# irb(main):030:0> User.connection.schema_cache.instance_variable_get(:@columns_hash)
# {}

# irb(main):035:0> ActiveRecord::Base.connection == User.connection
# true

# irb(main):010:0> ActiveRecord::Base.connection.columns(User.table_name)
# [
#     [0] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10ff8 @name="id", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a12df8 @sql_type="INTEGER", @type=:integer, @limit=nil, @precision=nil, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [1] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10e68 @name="name", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a10f58 @sql_type="varchar", @type=:string, @limit=nil, @precision=nil, @scale=nil>, @null=true, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [2] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10d28 @name="created_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a10e18 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [3] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10be8 @name="updated_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a10e18 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>
# ]
# irb(main):011:0> ActiveRecord::Base.connection.schema_cache.columns(User.table_name)
# [
#     [0] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10ff8 @name="id", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a12df8 @sql_type="INTEGER", @type=:integer, @limit=nil, @precision=nil, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [1] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10e68 @name="name", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a10f58 @sql_type="varchar", @type=:string, @limit=nil, @precision=nil, @scale=nil>, @null=true, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [2] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10d28 @name="created_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a10e18 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>,
#     [3] #<ActiveRecord::ConnectionAdapters::Column:0x0000000114a10be8 @name="updated_at", @sql_type_metadata=#<ActiveRecord::ConnectionAdapters::SqlTypeMetadata:0x0000000114a10e18 @sql_type="datetime(6)", @type=:datetime, @limit=nil, @precision=6, @scale=nil>, @null=false, @default=nil, @default_function=nil, @collation=nil, @comment=nil>
# ]

# activerecord-7.0.7/lib/active_record/schema_dumper.rb
# irb(main):002:0> ActiveRecord::SchemaDumper.dump
#   ActiveRecord::SchemaMigration Pluck (0.1ms)  SELECT "schema_migrations"."version" FROM "schema_migrations" ORDER BY "schema_migrations"."version" ASC
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

# ActiveRecord::Schema[7.0].define(version: 2023_08_14_003247) do
#   create_table "companies", force: :cascade do |t|
#     t.string "name"
#     t.datetime "created_at", null: false
#     t.datetime "updated_at", null: false
#   end

#   create_table "employments", force: :cascade do |t|
#     t.integer "company_id", null: false
#     t.integer "user_id", null: false
#     t.datetime "created_at", null: false
#     t.datetime "updated_at", null: false
#     t.index ["company_id"], name: "index_employments_on_company_id"
#     t.index ["user_id"], name: "index_employments_on_user_id"
#   end

#   create_table "users", force: :cascade do |t|
#     t.string "name"
#     t.datetime "created_at", null: false
#     t.datetime "updated_at", null: false
#     t.string "extra_col"
#   end

#   add_foreign_key "employments", "companies"
#   add_foreign_key "employments", "users"
# end

# irb(main):003:0> ActiveRecord::Base.connection.tables
# [
#     [0] "schema_migrations",
#     [1] "ar_internal_metadata",
#     [2] "companies",
#     [3] "employments",
#     [4] "users"
# ]

# irb(main):025:0> User.attribute_types.first.last.class.ancestors
# [
#     [ 0] ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer < ActiveModel::Type::Integer,
#     [ 1] ActiveModel::Type::Integer < ActiveModel::Type::Value,
#     [ 2] ActiveModel::Type::Helpers::Numeric,
#     [ 3] ActiveModel::Type::Value < Object, # ! This is key ---> ActiveModel::Type::Value has a #type method
#     [ 4] ActiveSupport::Dependencies::RequireDependency,
#     [ 5] ActiveSupport::ToJsonWithActiveSupportEncoder,
#     [ 6] Object < BasicObject,
#     [ 7] PP::ObjectMixin,
#     [ 8] JSON::Ext::Generator::GeneratorMethods::Object,
#     [ 9] ActiveSupport::Tryable,
#     [10] DEBUGGER__::TrapInterceptor,
#     [11] Kernel,
#     [12] BasicObject
# ]
# irb(main):026:0> pp User.attribute_types.first.last
# #<ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer:0x0000000106ef63c8
#  @limit=nil,
#  @precision=nil,
#  @range=-9223372036854775808...9223372036854775808,
#  @scale=nil>
# #<ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer:0x0000000106ef63c8 @precision=nil, @scale=nil, @limit=nil, @range=-9223372036854775808...9223372036854775808>
# irb(main):027:0> pp User.attribute_types.first.last.type
# :integer
# :integer
# irb(main):028:0>

# irb(main):029:0> User.attribute_types
# {
#             "id" => #<ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer:0x0000000106ef63c8 @precision=nil, @scale=nil, @limit=nil, @range=-9223372036854775808...9223372036854775808>,
#           "name" => #<ActiveModel::Type::String:0x0000000106ef4528 @true="t", @false="f", @precision=nil, @scale=nil, @limit=nil>,
#     "created_at" => #<ActiveRecord::Type::DateTime:0x00000001066b5d08 @precision=6, @scale=nil, @limit=nil>,
#     "updated_at" => #<ActiveRecord::Type::DateTime:0x00000001066b5d08 @precision=6, @scale=nil, @limit=nil>,
#      "extra_col" => #<ActiveModel::Type::String:0x0000000106ef4528 @true="t", @false="f", @precision=nil, @scale=nil, @limit=nil>
# }

# irb(main):028:0> User.attribute_types.map{ |k, v| [k, v.type] }.to_h
# {
#             "id" => :integer,
#           "name" => :string,
#     "created_at" => :datetime,
#     "updated_at" => :datetime,
#      "extra_col" => :string
# }
# irb(main):029:0>

# ActiveRecord::Type.registry.instance_variable_get(:@registrations).map{ |r| r.instance_variable_get(:@name) }
# [
#     [ 0] :big_integer,
#     [ 1] :binary,
#     [ 2] :boolean,
#     [ 3] :date,
#     [ 4] :datetime,
#     [ 5] :decimal,
#     [ 6] :float,
#     [ 7] :integer,
#     [ 8] :immutable_string,
#     [ 9] :json,
#     [10] :string,
#     [11] :text,
#     [12] :time,
#     [13] :integer
# ]

# irb(main):055:0> ActiveRecord::Base.connection.type_to_sql("string")
# "varchar"
# irb(main):056:0> ActiveRecord::Base.connection.type_to_sql(:string)
# "varchar"
# irb(main):057:0> ActiveRecord::Base.connection.type_to_sql(:big_integer)
# "big_integer"
# irb(main):058:0> ActiveRecord::Base.connection.type_to_sql(:bidjfid)
# "bidjfid"
# irb(main):059:0> ActiveRecord::Base.connection.type_to_sql(:binary)
# "blob"
# irb(main):060:0> ActiveRecord::Base.connection.type_to_sql(:bimmutable_string)
# "bimmutable_string"
# irb(main):061:0> ActiveRecord::Base.connection.type_to_sql(:immutable_string)
# "immutable_string"
# irb(main):062:0> ActiveRecord::Base.connection.type_to_sql(:json)
# "json"
# irb(main):063:0> ActiveRecord::Base.connection.type_to_sql(:text)
# "text"
# irb(main):064:0> ActiveRecord::Base.connection.type_to_sql(:time)
# "time"
# irb(main):065:0> ActiveRecord::Base.connection.type_to_sql(:integer)
# "integer"
# irb(main):066:0> ActiveRecord::Base.connection.type_to_sql(:date)
# "date"
# irb(main):067:0> ActiveRecord::Base.connection.type_to_sql(:datetime)
# "datetime"
# irb(main):068:0> ActiveRecord::Base.connection.type_to_sql(:boolean)
# "boolean"
# irb(main):069:0> ActiveRecord::Base.connection.type_to_sql("boolean")
# "boolean"
# irb(main):070:0> ActiveRecord::Base.connection.type_to_sql("float")
# "float"
# irb(main):071:0> ActiveRecord::Base.connection.type_to_sql(:float)
# "float"
# irb(main):072:0> ActiveRecord::Base.connection.type_to_sql(:string)
# "varchar"

# irb(main):073:0> ActiveRecord::Base.connection.native_database_types
# {
#     :primary_key => "integer PRIMARY KEY AUTOINCREMENT NOT NULL",
#          :string => {
#         :name => "varchar"
#     },
#            :text => {
#         :name => "text"
#     },
#         :integer => {
#         :name => "integer"
#     },
#           :float => {
#         :name => "float"
#     },
#         :decimal => {
#         :name => "decimal"
#     },
#        :datetime => {
#         :name => "datetime"
#     },
#            :time => {
#         :name => "time"
#     },
#            :date => {
#         :name => "date"
#     },
#          :binary => {
#         :name => "blob"
#     },
#         :boolean => {
#         :name => "boolean"
#     },
#            :json => {
#         :name => "json"
#     }
# }
