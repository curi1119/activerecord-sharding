require "active_support/concern"

module ActiveRecord
  module Sharding
    module Model
      extend ActiveSupport::Concern

      included do |base|
        base.before_create :validate_id!

        class_attribute :cluster_router, instance_writer: false
        class_attribute :shard_repository, instance_writer: false
        class_attribute :sharding_key, instance_writer: false
      end

      module ClassMethods
        def use_sharding(name, algorithm = :modulo)
          config = ActiveRecord::Sharding.config.fetch_cluster_config name
          if algorithm == :modulo
            self.cluster_router = ActiveRecord::Sharding::ModuloRouter.new config
          end
          self.shard_repository = ActiveRecord::Sharding::ShardRepository.new config, self
          self.abstract_class = true
        end

        def define_sharding_key(column)
          self.sharding_key = column.to_sym
        end

        def before_put(&block)
          @before_put_callback = block
        end

        def put!(attributes)
          raise "`sharding_key` is not defined. Use `define_sharding_key`." unless sharding_key

          @before_put_callback.call(attributes) if @before_put_callback

          if key = attributes[sharding_key] || attributes[sharding_key.to_s]
            if block_given?
              shard_for(key).transaction do
                object = shard_for(key).create!(attributes)
                yield(object)
              end
            else
              shard_for(key).create!(attributes)
            end
          else
            raise ActiveRecord::Sharding::MissingShardingKeyAttribute
          end
        end

        def shard_for(key)
          connection_name = cluster_router.route key
          shard_repository.fetch connection_name
        end

        def all_shards
          shard_repository.all
        end

        def all_shards_in_parallel
          AllShardsInParallel.new(all_shards)
        end
        alias_method :parallel, :all_shards_in_parallel

        def define_parent_methods(&block)
          instance_eval(&block)
        end
      end

      private

        def validate_id!
          raise ActiveRecord::Sharding::MissingPrimaryKey if attributes[self.class.primary_key].nil?
          raise ActiveRecord::Sharding::InvalidPrimaryKey if attributes[self.class.primary_key].zero?
        end
    end
  end
end
