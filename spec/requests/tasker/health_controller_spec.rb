# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../examples/test_authenticator'
require_relative '../../examples/custom_authorization_coordinator'

RSpec.describe 'Health API', type: :request do
  around do |example|
    # Store original configuration
    original_config = Tasker::Configuration.configuration.dup

    # Configure basic health settings for tests
    Tasker.configure do |config|
      config.health do |health|
        health.cache_duration_seconds = 30
      end
      config.auth do |auth|
        auth.authentication_enabled = false
        auth.authorization_enabled = false
      end
    end

    example.run

    # Restore original configuration
    Tasker.instance_variable_set(:@configuration, original_config)
  end

  path '/tasker/health/ready' do
    get('readiness check') do
      tags 'Health'
      description 'Check if the system is ready to accept requests. This endpoint never requires authentication.'
      operationId 'checkReadiness'
      produces 'application/json'

      response(200, 'system is ready') do
        before do
          allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({
            ready: true,
            checks: { database: { status: 'ok' } },
            timestamp: Time.current
          })
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)
          expect(json_response['ready']).to be true
        end
      end

      response(503, 'system is not ready') do
        before do
          allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({
            ready: false,
            checks: { database: { status: 'error', message: 'Connection failed' } },
            timestamp: Time.current
          })
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:service_unavailable)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)
          expect(json_response['ready']).to be false
        end
      end

      response(503, 'exception during health check') do
        before do
          allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_raise(StandardError.new('Unexpected error'))
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:service_unavailable)
          json_response = JSON.parse(response.body)
          expect(json_response['ready']).to be false
          expect(json_response['error']).to eq('Health check failed')
          expect(json_response['message']).to include('Unexpected error')
        end
      end
    end
  end

  path '/tasker/health/live' do
    get('liveness check') do
      tags 'Health'
      description 'Check if the system is alive and responding. This endpoint never requires authentication.'
      operationId 'checkLiveness'
      produces 'application/json'

      response(200, 'system is alive') do
        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)
          expect(json_response['alive']).to be true
          expect(json_response['service']).to eq('tasker')
          expect(json_response['timestamp']).to be_present
        end
      end
    end
  end

  path '/tasker/health/status' do
    get('detailed health status') do
      tags 'Health'
      description 'Get detailed system health status including metrics and database information. May require authorization depending on configuration.'
      operationId 'getHealthStatus'
      produces 'application/json'

      response(200, 'healthy system status') do
        before do
          allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
            healthy: true,
            timestamp: Time.current,
            metrics: { tasks: { total: 0 } },
            database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 }
          })
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)
          expect(json_response['healthy']).to be true
        end
      end

      response(503, 'unhealthy system status') do
        before do
          allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
            healthy: false,
            timestamp: Time.current,
            error: 'Database connection failed'
          })
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:service_unavailable)
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)
          expect(json_response['healthy']).to be false
          expect(json_response['error']).to include('Database connection failed')
        end
      end

      response(503, 'status check exception') do
        before do
          allow(Tasker::Health::StatusChecker).to receive(:status).and_raise(StandardError.new('Status error'))
        end

        after do |example|
          example.metadata[:response][:content] = {
            'application/json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end

        run_test! do |response|
          expect(response).to have_http_status(:service_unavailable)
          json_response = JSON.parse(response.body)
          expect(json_response['healthy']).to be false
          expect(json_response['error']).to eq('Status check failed')
          expect(json_response['message']).to include('Status error')
        end
      end
    end
  end

  # Test authentication scenarios as separate contexts
  describe 'authentication scenarios' do
    it 'never requires authentication for ready endpoint' do
      original_config = Tasker::Configuration.configuration.dup

      # Configure authentication and authorization as enabled
      Tasker.configure do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authorization_enabled = true
          auth.authenticator_class = 'TestAuthenticator'
          auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
        end
      end

      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({
        ready: true,
        checks: {},
        timestamp: Time.current
      })

      # Should work without any authentication/authorization headers
      get '/tasker/health/ready'

      expect(response).to have_http_status(:ok)

      # Restore configuration
      Tasker.instance_variable_set(:@configuration, original_config)
    end

    it 'never requires authentication for live endpoint' do
      original_config = Tasker::Configuration.configuration.dup

      # Configure authentication and authorization as enabled
      Tasker.configure do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authorization_enabled = true
          auth.authenticator_class = 'TestAuthenticator'
          auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
        end
      end

      # Should work without any authentication/authorization headers
      get '/tasker/health/live'

      expect(response).to have_http_status(:ok)

      # Restore configuration
      Tasker.instance_variable_set(:@configuration, original_config)
    end

    context 'status endpoint with authorization enabled' do
      around do |example|
        original_config = Tasker::Configuration.configuration.dup
        example.run
        Tasker.instance_variable_set(:@configuration, original_config)
      end

      before do
        Tasker.configure do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authorization_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
            auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
          end
        end

        # Mock successful authentication
        allow_any_instance_of(TestAuthenticator).to receive(:authenticate!).and_return(true)
        allow_any_instance_of(TestAuthenticator).to receive(:authenticated?).and_return(true)

        # Mock healthy status
        allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
          healthy: true,
          timestamp: Time.current,
          metrics: { tasks: { total: 0 } },
          database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 }
        })
      end

      it 'requires health_status.index authorization' do
        # Mock user without health_status.index permission
        unauthorized_user = double('User',
          id: 1,
          tasker_admin?: false,
          has_tasker_permission?: false
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(unauthorized_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer valid-token' }

        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Forbidden')
        expect(json_response['message']).to be_present
      end

      it 'allows access for admin users' do
        # Mock admin user
        admin_user = double('User',
          id: 1,
          tasker_admin?: true,
          has_tasker_permission?: false
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(admin_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer admin-token' }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be true
      end

      it 'allows access for users with health_status.index permission' do
        # Mock user with health_status.index permission
        authorized_user = double('User',
          id: 1,
          tasker_admin?: false,
          has_tasker_permission?: ->(permission) { permission == 'tasker.health_status:index' }
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(authorized_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer authorized-token' }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be true
      end

      it 'handles authorization coordinator errors gracefully' do
        # Mock authorization coordinator error - use the correct error type
        allow_any_instance_of(CustomAuthorizationCoordinator).to receive(:authorize!).and_raise(Tasker::Authorization::ConfigurationError.new('Authorization system error'))

        authorized_user = double('User', id: 1)
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(authorized_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer valid-token' }

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Authorization Configuration Error')
        expect(json_response['message']).to include('Authorization system error')
      end
    end
  end

  describe 'caching behavior' do
    around do |example|
      # Use memory store for actual caching behavior
      original_cache_store = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      Rails.cache.clear

      original_config = Tasker::Configuration.configuration.dup

      Tasker.configure do |config|
        config.auth do |auth|
          auth.authorization_enabled = false
        end
      end

      example.run

      Tasker.instance_variable_set(:@configuration, original_config)
      Rails.cache.clear
      Rails.cache = original_cache_store
    end

    it 'uses cached results for status endpoint' do
      # Mock StatusChecker to return consistent data and avoid database issues
      status_data = {
        healthy: true,
        timestamp: Time.current,
        metrics: { tasks: { total: 5 } },
        database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 }
      }
      allow(Tasker::Health::StatusChecker).to receive(:status).and_return(status_data)

      # Mock database queries to avoid transaction issues
      allow(Tasker::Task).to receive(:where).and_return(double(count: 0))
      allow(Tasker::WorkflowStep).to receive(:joins).and_return(double(where: double(where: double(count: 0))))

      # Mock the controller's database-related methods
      allow_any_instance_of(Tasker::HealthController).to receive(:calculate_performance_trends).and_return({
        task_creation_rate: 0,
        completion_rate: 0,
        error_rate: 0,
        avg_step_duration: 0.0
      })

      # Test caching by verifying that both responses have the same data
      # First request should generate data and cache it
      get '/tasker/health/status'
      expect(response).to have_http_status(:ok)
      first_response = JSON.parse(response.body)

      expect(first_response['healthy']).to be true
      expect(first_response['metrics']).to be_present

      # Second request should get cached data
      get '/tasker/health/status'
      expect(response).to have_http_status(:ok)
      second_response = JSON.parse(response.body)

      expect(second_response['healthy']).to be true
      expect(second_response['metrics']).to be_present

      # Both responses should have the same structure (indicating caching worked)
      expect(first_response['metrics']['tasks']['total']).to eq(second_response['metrics']['tasks']['total'])

      # Verify cache info is present (indicating intelligent caching is working)
      expect(first_response['cache_info']).to be_present
      expect(second_response['cache_info']).to be_present
    end
  end

  describe 'response headers' do
    before do
      Tasker.configure do |config|
        config.auth do |auth|
          auth.authorization_enabled = false
        end
      end
    end

    it 'sets appropriate content type for all endpoints' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({ ready: true, checks: {}, timestamp: Time.current })
      allow(Tasker::Health::StatusChecker).to receive(:status).and_return({ healthy: true, timestamp: Time.current, metrics: { tasks: { total: 0 } }, database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 } })

      get '/tasker/health/ready'
      expect(response.content_type).to eq('application/json; charset=utf-8')

      get '/tasker/health/live'
      expect(response.content_type).to eq('application/json; charset=utf-8')

      get '/tasker/health/status'
      expect(response.content_type).to eq('application/json; charset=utf-8')
    end

    it 'sets cache control headers appropriately' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({ ready: true, checks: {}, timestamp: Time.current })

      get '/tasker/health/ready'
      # Rails may override the header, but it should prevent caching
      expect(response.headers['Cache-Control']).to match(/no-cache|no-store/)
    end
  end
end
