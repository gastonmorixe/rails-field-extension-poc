# frozen_string_literal: true

# Provides enforcement of declared field for ActiveRecord models.
module FieldEnforcement
  module Utils
    class PendingFieldEnforcementMigrationError < StandardError
      include ActiveSupport::ActionableError

      action 'Update snapshot' do
        models = FieldEnforcement::Utils.active_record_models
        FieldEnforcement::Utils.store_field_snapshot(models)
      end

      action 'Write migrations' do
        models = FieldEnforcement::Utils.active_record_models
        changes = FieldEnforcement::Utils.detect_changes(models)
        FieldEnforcement::Utils.generate_migrations(changes, write: true)
        # TODO: save the last field snapshot updated at somewhere and compare with last mgiration
        FieldEnforcement::Utils.store_field_snapshot(models, write: true)
      end

      action 'Run db:migrations' do
        ActiveRecord::Tasks::DatabaseTasks.migrate
      end
    end

    class << self
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

      def active_record_models
        Rails.application.eager_load! # Ensure all models are loaded

        ActiveRecord::Base.descendants.reject do |model|
          !(model.is_a?(Class) && model < ApplicationRecord) ||
            model.abstract_class? ||
            model.name.nil? ||
            model.name == 'ActiveRecord::SchemaMigration'
        end
      end

      def store_field_snapshot(models, write: false)
        snapshot = models.map do |model|
          [model.name, model.declared_fields.map { |f| [f.name, f.type.to_s] }.to_h]
        end.to_h

        snapshot[:__metadata__] = {
          updated_at: Time.now.utc.strftime('%Y%m%d%H%M%S')
        }

        snapshot_in_json = JSON.pretty_generate(snapshot)
        puts snapshot_in_json

        if write == true
          snapshot_path = Rails.root.join('db', 'field_snapshot.json')
          File.write(snapshot_path, snapshot_in_json)
          puts "Field snapshot file udpated #{snapshot_path}"
        end

        snapshot_in_json
      end

      def detect_changes(models)
        changes = {}

        # Load the snapshot
        snapshot_path = Rails.root.join('db', 'field_snapshot.json')
        snapshot = JSON.parse(File.read(snapshot_path))

        snapshot_metadata = snapshot[:__metadata__]
        puts "snapshot_metadata: #{snapshot_metadata}"
        snapshot.delete(:__metadata__)

        models.each do |model|
          model_name = model.name
          declared_fields = model.declared_fields.map { |f| [f.name, f.type] }.to_h # f.type.to_s
          previous_fields = snapshot[model_name] || {}

          # Detect changes
          model_changes = {
            added: [],
            removed: [],
            renamed: [],
            type_changed: []
          }

          declared_fields.each do |name, type|
            if previous_fields[name]
              if previous_fields[name] != type.to_s
                model_changes[:type_changed] << { name:, from: previous_fields[name], to: type }
              end
            else
              # Check for renames
              renamed_from = previous_fields.keys.find do |prev_name|
                previous_fields[prev_name] == type.to_s && !declared_fields[prev_name]
              end
              if renamed_from
                model_changes[:renamed] << { from: renamed_from, to: name }
              else
                model_changes[:added] << { name:, type: }
              end
            end
          end

          previous_fields.each do |name, _|
            model_changes[:removed] << ({ name: }) unless declared_fields[name]
          end

          changes[model_name] = model_changes unless model_changes.values.all?(&:empty?)
        end

        # Update the snapshot
        # store_field_snapshot(models)

        changes
      end

      def generate_migrations(changes, write: false)
        puts "\n\nMigrations code:\n\n"

        index = 0
        changes.map do |model_name, model_changes|
          migration_class_name = "#{model_name}Migration"

          migration_code = []
          migration_code << "class #{migration_class_name} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]"
          migration_code << '  def change'

          model_changes[:added].each do |change|
            field_type = change[:type]
            puts field_type
            puts field_type.class
            field_type_for_db = GQL_TO_RAILS_TYPE_MAP[field_type]
            puts GQL_TO_RAILS_TYPE_MAP
            migration_code << "    add_column :#{model_name.tableize}, :#{change[:name]}, :#{field_type_for_db}"
          end

          model_changes[:removed].each do |change|
            migration_code << "    remove_column :#{model_name.tableize}, :#{change[:name]}"
          end

          # TODO: Improve rename algo for fields with same type
          model_changes[:renamed].each do |change|
            migration_code << "    rename_column :#{model_name.tableize}, :#{change[:from]}, :#{change[:to]}"
          end

          model_changes[:type_changed].each do |change|
            migration_code << "    change_column :#{model_name.tableize}, :#{change[:name]}, :#{change[:to]}"
          end

          migration_code << '  end'
          migration_code << 'end'

          puts migration_code
          puts "\n"

          migration_filename = nil
          if write == true
            migration_filename = "#{Time.now.utc.strftime('%Y%m%d%H%M%S').to_i + index}_#{migration_class_name.underscore}.rb"
            migration_path = Rails.root.join('db', 'migrate', migration_filename)
            File.write(migration_path, migration_code.join("\n"))
            puts "Migration saved at #{migration_path}"
          end

          index += 1

          [migration_code, migration_filename]
        end
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
          extra_fields = extra_fields.filter { |f| !respond_to?(f) }
          associations_columns = self.class.reflections.values.map do |r|
            r.foreign_key
          end
          missing_fields = database_columns - declared_fields_names - associations_columns

          puts "debug: extra_fields: #{extra_fields}"
          puts "debug: missing_fields: #{missing_fields}"

          models = FieldEnforcement::Utils.active_record_models
          changes = FieldEnforcement::Utils.detect_changes(models)
          # FieldEnforcement::Utils.store_field_snapshot(models)
          migrations = FieldEnforcement::Utils.generate_migrations(changes)

          puts "----------\n\n\n"
          puts "changes: #{changes}"
          puts "migration: #{migrations}"
          puts "----------\n\n\n"

          # extra_fields.each do |field_name|
          #   # Generate the migration code for this field
          #   # field = self.class.declared_fields.find { |df| df.name == field_name }
          #   # migration_code = FieldEnforcement::Utils.generate_migration_code(self, field.name, field.type)

          #   error_message = "Declared field '#{field_name}' not found in db for model #{self.class.name}."
          #   puts "\n\n\n----------\n"
          #   puts error_message
          #   # puts "This is what the migration should look like:\n\n"
          #   # puts "# #{migration_code[0]}"
          #   # puts migration_code[1]
          #   puts "----------\n\n\n"
          #   raise error_message
          #   # puts 'Do you want to generate it? [y/N]'

          #   # response = gets.chomp
          #   # if response.downcase == 'y'
          #   #   # TODO: create_migration_file(self.class.name, field, migration_code)
          #   #   puts "Migration created! Don't forget to run the migration."
          #   # else
          #   #   puts 'Migration was not created.'
          #   # end
          # end

          # TODO: Throw changes diff and migration code to web
          # TODO: Throw if a method is defined and it doesn't have a field (unless it's private?)

          unless extra_fields.empty?
            error_message = "Detected declared extra field#{extra_fields.size > 1 ? 's' : ''} in #{self.class.name}: #{extra_fields.join(', ')}. Please create the appropiate db migration or define the method#{extra_fields.size > 1 ? 's' : ''} in the model."
            raise Utils::PendingFieldEnforcementMigrationError.new(error_message)
          end

          unless missing_fields.empty?
            error_message = "fields must be declared in #{self.class.name}: #{missing_fields.join(', ')}"
            raise Utils::PendingFieldEnforcementMigrationError.new(error_message)
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
