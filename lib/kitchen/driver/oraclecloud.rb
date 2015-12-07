#
# Author:: Chef Partner Engineering (<partnereng@chef.io>)
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'kitchen'
require 'oraclecloud'
require 'securerandom'
require_relative 'oraclecloud_version'

module Kitchen
  module Driver
    class Oraclecloud < Kitchen::Driver::Base # rubocop:disable Metrics/ClassLength
      kitchen_driver_api_version 2
      plugin_version Kitchen::Driver::ORACLECLOUD_VERSION

      required_config :username
      required_config :password
      required_config :api_url
      required_config :identity_domain
      required_config :shape
      required_config :image

      default_config :verify_ssl, true
      default_config :wait_time, 600
      default_config :refresh_time, 2
      default_config :sshkeys, []
      default_config :description, nil
      default_config :project_name, nil
      default_config :public_ip, nil

      def name
        'OracleCloud'
      end

      def create(state)
        return if state[:orchestration_id]

        info('Creating Oracle Cloud orchestration...')
        orchestration

        info("Orchestration #{orchestration.name_with_container} created. Starting...")
        orchestration.start
        wait_for_status(orchestration, 'ready')

        state[:orchestration_id] = orchestration.name_with_container

        ip_address = server_ip_address
        raise 'No IP address returned for Oracle Cloud instance' if ip_address.nil?

        state[:hostname] = ip_address

        wait_for_server(state)
        info("Server #{orchestration_name} ready.")
      end

      def destroy(state)
        return if state[:orchestration_id].nil?

        info("Looking up orchestration #{state[:orchestration_id]}...")

        begin
          orchestration(state[:orchestration_id])
        rescue OracleCloud::Exception::HTTPNotFound
          warn("No orchestration found with ID #{state[:orchestration_id]}, assuming it has been destroyed already.")
          return
        end

        info("Stopping orchestration #{orchestration.name_with_container} and associated instance...")
        orchestration.stop
        wait_for_status(orchestration, 'stopped')

        info("Deleting orchestration #{orchestration.name_with_container} and associated instance...")
        orchestration.delete
        info('Orchestration deleted.')
      end

      def oraclecloud_client
        @client ||= OracleCloud::Client.new(
          username:        config[:username],
          password:        config[:password],
          api_url:         config[:api_url],
          identity_domain: config[:identity_domain],
          verify_ssl:      config[:verify_ssl]
        )
      end

      def orchestration(name = nil)
        return @orchestration if @orchestration

        if name
          @orchestration = oraclecloud_client.orchestrations.by_name(name)
        else
          @orchestration = oraclecloud_client.orchestrations.create(
            name: orchestration_name,
            description: description,
            instances: [ instance_request ]
          )
        end

        @orchestration
      end

      def instance_request
        oraclecloud_client.instance_request(
          name:      orchestration_name,
          shape:     config[:shape],
          imagelist: config[:image],
          sshkeys:   sshkeys,
          public_ip: public_ip
        )
      end

      def server
        @server ||= orchestration.instances.first
      end

      def server_ip_address
        public_ips = server.public_ip_addresses
        public_ips.empty? ? server.ip_address : public_ips.first
      end

      def wait_for_server(state)
        info("Server #{orchestration_name} created. Waiting until ready...")
        begin
          instance.transport.connection(state).wait_until_ready
        rescue
          error("Server #{orchestration_name} not reachable. Destroying server...")
          destroy(state)
          raise
        end
      end

      def wait_for_status(item, requested_status)
        last_status = ''

        begin
          Timeout.timeout(wait_time) do
            loop do
              item.refresh
              current_status = item.status

              if item.error?
                error_str = "Request encountered an error: #{item.errors}"
                error(error_str)
                raise error_str
              end

              unless last_status == current_status
                last_status = current_status
                info("Current status: #{current_status}.")
              end

              break if current_status == requested_status

              sleep refresh_time
            end
          end
        rescue Timeout::Error
          error("Request did not complete in #{wait_time} seconds. Check the Oracle Cloud Web UI for more information.")
          raise
        end
      end

      def wait_time
        config[:wait_time].to_i
      end

      def refresh_time
        config[:refresh_time].to_i
      end

      def description
        config[:description].nil? ? "#{instance.name} for #{username} via Test Kitchen" : config[:description]
      end

      def username
        config[:username]
      end

      def orchestration_name
        "TK-#{project_name}-#{instance.name.gsub(/\s+/, '')}"
      end

      def project_name
        @project_name ||= config[:project_name].nil? ? SecureRandom.uuid : config[:project_name].gsub(/\s+/, '')
      end

      def sshkeys
        config[:sshkeys].map { |key| "#{oraclecloud_client.full_identity_domain}/#{key}" }
      end

      def public_ip
        return nil unless config[:public_ip]

        (config[:public_ip] == 'pool') ? :pool : "ipreservation:#{config[:public_ip]}"
      end
    end
  end
end
