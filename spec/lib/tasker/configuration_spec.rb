# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe Tasker::Configuration, type: :model do
  let(:config) { described_class.new }

  before do
    # Reset to default configuration before each test
    Tasker.reset_configuration!
  end

  # Ensure configuration state is reset between tests
  around do |example|
    original_config = described_class.configuration.dup
    example.run
    Tasker.instance_variable_set(:@configuration, original_config)
  end

  describe '#identity_strategy_instance' do
    it 'returns a default IdentityStrategy when identity_strategy is :default' do
      # Store original configuration to restore later
      original_strategy = described_class.configuration.engine.identity_strategy

      # Test setting and getting the identity strategy
      config.engine do |engine|
        engine.identity_strategy = :default
      end

      # Check the updated strategy and its instance
      expect(config.engine.identity_strategy).to eq(:default)
      expect(config.engine.identity_strategy_instance).to be_a(Tasker::IdentityStrategy)

      # Restore original configuration
      described_class.configuration do |global_config|
        global_config.engine do |engine|
          engine.identity_strategy = original_strategy
        end
      end
    end

    it 'returns a HashIdentityStrategy when identity_strategy is :hash' do
      config.engine do |engine|
        engine.identity_strategy = :hash
      end

      expect(config.engine.identity_strategy).to eq(:hash)
      expect(config.engine.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)
    end

    it 'returns a custom strategy when identity_strategy is :custom' do
      config.engine do |engine|
        engine.identity_strategy = :custom
        engine.identity_strategy_class = 'Tasker::HashIdentityStrategy'
      end

      expect(config.engine.identity_strategy).to eq(:custom)
      expect(config.engine.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)
    end

    it 'raises an error when :custom is selected but no class is provided' do
      config.engine do |engine|
        engine.identity_strategy = :custom
      end

      expect do
        config.engine.identity_strategy_instance
      end.to raise_error(ArgumentError,
                         /Custom identity strategy selected but no identity_strategy_class provided/)
    end

    it 'raises an error when :custom is selected with an invalid class name' do
      config.engine do |engine|
        engine.identity_strategy = :custom
        engine.identity_strategy_class = 'NonExistentClass'
      end

      expect do
        config.engine.identity_strategy_instance
      end.to raise_error(ArgumentError, /Invalid identity_strategy_class/)
    end

    it 'raises an error for an unknown strategy type' do
      config.engine do |engine|
        engine.identity_strategy = :unknown
      end

      expect { config.engine.identity_strategy_instance }.to raise_error(ArgumentError, /Unknown identity_strategy/)
    end
  end

  describe 'Tasker::Configuration.configuration' do
    it 'allows setting identity_strategy through the block syntax' do
      # Store original configuration to restore later
      original_strategy = described_class.configuration.engine.identity_strategy

      # Test setting and getting the identity strategy
      described_class.configuration do |config|
        config.engine do |engine|
          engine.identity_strategy = :hash
        end
      end

      # Check the updated strategy and its instance
      expect(described_class.configuration.engine.identity_strategy).to eq(:hash)
      expect(described_class.configuration.engine.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)

      # Restore original configuration
      described_class.configuration do |global_config|
        global_config.engine do |engine|
          engine.identity_strategy = original_strategy
        end
      end
    end
  end

  describe 'database configuration' do
    it 'has default database configuration values' do
      expect(config.database.name).to be_nil
      expect(config.database.enable_secondary_database).to be false
    end

    it 'allows setting database configuration' do
      config.database do |db|
        db.name = :tasker
        db.enable_secondary_database = true
      end

      expect(config.database.name).to eq(:tasker)
      expect(config.database.enable_secondary_database).to be true
    end

    it 'supports string database names' do
      config.database do |db|
        db.name = 'tasker_production'
        db.enable_secondary_database = true
      end

      expect(config.database.name).to eq('tasker_production')
    end
  end

  describe 'health configuration' do
    it 'has default health configuration values' do
      expect(config.health).to be_present
      expect(config.health.ready_requires_authentication).to be false
      expect(config.health.status_requires_authentication).to be true
    end

    it 'allows configuring health settings' do
      config.health do |health|
        health.ready_requires_authentication = true
        health.status_requires_authentication = false
      end

      expect(config.health.ready_requires_authentication).to be true
      expect(config.health.status_requires_authentication).to be false
    end

    it 'validates health configuration structure' do
      expect(config.health).to respond_to(:ready_requires_authentication)
      expect(config.health).to respond_to(:status_requires_authentication)
      # Dry-struct configurations are immutable, so no setter methods on the struct itself
      expect(config).to respond_to(:health) # block-based configuration is available
    end
  end

  describe 'health configuration integration' do
    it 'allows configuration via block' do
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = true
          health.status_requires_authentication = false
        end
      end

      expect(described_class.configuration.health.ready_requires_authentication).to be true
      expect(described_class.configuration.health.status_requires_authentication).to be false
    end

    it 'maintains configuration state across accesses' do
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = true
        end
      end

      # Access configuration multiple times
      first_access = described_class.configuration.health.ready_requires_authentication
      second_access = described_class.configuration.health.ready_requires_authentication

      expect(first_access).to be true
      expect(second_access).to be true
      expect(first_access).to eq(second_access)
    end

    it 'allows modification of existing configuration' do
      # Set initial configuration
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = false
        end
      end

      expect(described_class.configuration.health.ready_requires_authentication).to be false

      # Modify configuration
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = true
        end
      end

      expect(described_class.configuration.health.ready_requires_authentication).to be true
    end
  end

  describe 'health configuration validation' do
    it 'accepts boolean values for authentication requirements' do
      expect { config.health { |health| health.ready_requires_authentication = true } }.not_to raise_error
      expect { config.health { |health| health.ready_requires_authentication = false } }.not_to raise_error
      expect { config.health { |health| health.status_requires_authentication = true } }.not_to raise_error
      expect { config.health { |health| health.status_requires_authentication = false } }.not_to raise_error
    end

    it 'handles truthy/falsy values appropriately' do
      # Test truthy values
      config.health { |health| health.ready_requires_authentication = 'yes' }
      expect(config.health.ready_requires_authentication).to be_truthy

      config.health { |health| health.ready_requires_authentication = 1 }
      expect(config.health.ready_requires_authentication).to be_truthy

      # Test falsy values
      config.health { |health| health.ready_requires_authentication = nil }
      expect(config.health.ready_requires_authentication).to be_falsy

      config.health { |health| health.ready_requires_authentication = '' }
      expect(config.health.ready_requires_authentication).to be_falsy
    end
  end

  describe 'health configuration defaults' do
    it 'has sensible defaults for production use' do
      # Ready endpoint should not require auth by default (for K8s probes)
      expect(config.health.ready_requires_authentication).to be false

      # Status endpoint should require auth by default (contains sensitive info)
      expect(config.health.status_requires_authentication).to be true
    end

    it 'maintains consistent defaults across instances' do
      config1 = described_class.new
      config2 = described_class.new

      expect(config1.health.ready_requires_authentication).to eq(config2.health.ready_requires_authentication)
      expect(config1.health.status_requires_authentication).to eq(config2.health.status_requires_authentication)
    end
  end

  describe 'health configuration interaction with other settings' do
    it 'works alongside authentication configuration' do
      Tasker.configure do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'TestAuthenticator'
        end
        config.health do |health|
          health.ready_requires_authentication = true
          health.status_requires_authentication = true
        end
      end

      expect(described_class.configuration.auth.authentication_enabled).to be true
      expect(described_class.configuration.health.ready_requires_authentication).to be true
      expect(described_class.configuration.health.status_requires_authentication).to be true
    end

    it 'maintains independence from other configuration sections' do
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = true
        end
      end

      # Other configuration sections should not be affected
      expect(described_class.configuration.auth.authentication_enabled).to be false # default
      expect(described_class.configuration.health.ready_requires_authentication).to be true
    end
  end

  describe 'health configuration serialization' do
    it 'can be duplicated properly' do
      original_config = described_class.new
      original_config.health do |health|
        health.ready_requires_authentication = true
        health.status_requires_authentication = false
      end

      duplicated_config = original_config.dup

      expect(duplicated_config.health.ready_requires_authentication).to be true
      expect(duplicated_config.health.status_requires_authentication).to be false

      # Modifications to duplicate should not affect original
      duplicated_config.health do |health|
        health.ready_requires_authentication = false
      end
      expect(original_config.health.ready_requires_authentication).to be true
    end

    it 'preserves health configuration in dup operations' do
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = true
          health.status_requires_authentication = false
        end
      end

      original_config = described_class.configuration
      duplicated_config = original_config.dup

      expect(duplicated_config.health.ready_requires_authentication).to eq(original_config.health.ready_requires_authentication)
      expect(duplicated_config.health.status_requires_authentication).to eq(original_config.health.status_requires_authentication)
    end
  end

  describe 'health configuration edge cases' do
    it 'handles nil health configuration gracefully' do
      # Health configuration should never be nil
      expect(config.health).not_to be_nil
      expect(config.health.ready_requires_authentication).to be_in([true, false])
      expect(config.health.status_requires_authentication).to be_in([true, false])
    end

    it 'handles rapid configuration changes' do
      # Rapidly change configuration
      10.times do |i|
        config.health do |health|
          health.ready_requires_authentication = i.even?
        end
      end

      # Final state should be consistent
      expect(config.health.ready_requires_authentication).to be false # 9 is odd, so final value is false
    end

    it 'maintains thread safety for configuration access' do
      Tasker.configure do |config|
        config.health do |health|
          health.ready_requires_authentication = true
        end
      end

      threads = []
      results = []

      # Access configuration from multiple threads
      5.times do
        threads << Thread.new do
          results << described_class.configuration.health.ready_requires_authentication
        end
      end

      threads.each(&:join)

      # All threads should see the same configuration
      expect(results).to all(be true)
      expect(results.size).to eq(5)
    end
  end
end
