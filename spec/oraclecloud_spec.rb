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

require 'spec_helper'
require 'oraclecloud'
require 'kitchen/driver/oraclecloud'
require 'kitchen/provisioner/dummy'
require 'kitchen/transport/dummy'
require 'kitchen/verifier/dummy'

describe Kitchen::Driver::Oraclecloud do
  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:platform)      { Kitchen::Platform.new(name: 'fake_platform') }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:driver)        { Kitchen::Driver::Oraclecloud.new(config) }

  let(:config) do
    {
      api_url:         'https://testcloud.oracle.com',
      username:        'test_user',
      password:        'test_password',
      identity_domain: 'test_domain',
      shape:           'test_shape',
      image:           'test_image',
      verify_ssl:      true
    }
  end

  let(:instance) do
    instance_double(Kitchen::Instance,
                    logger:    logger,
                    transport: transport,
                    platform:  platform,
                    to_str:    'instance_str'
                   )
  end

  before do
    allow(driver).to receive(:instance).and_return(instance)
  end

  it 'driver API version is 2' do
    expect(driver.diagnose_plugin[:api_version]).to eq(2)
  end

  describe '#name' do
    it 'has an overridden name' do
      expect(driver.name).to eq('OracleCloud')
    end
  end

  describe '#create' do
    let(:state) { {} }
    let(:orchestration) { double('orchestration') }

    before do
      allow(driver).to receive(:orchestration).and_return(orchestration)
      allow(driver).to receive(:wait_for_status)
      allow(driver).to receive(:wait_for_server)
      allow(driver).to receive(:server_ip_address).and_return('1.2.3.4')
      allow(instance).to receive(:name).and_return('instance_name')
      allow(orchestration).to receive(:start)
      allow(orchestration).to receive(:name_with_container)
    end

    context 'when the server is already created' do
      let(:state) { { orchestration_id: 'orch1' } }

      it 'does not create an orchestration' do
        expect(driver).not_to receive(:orchestration)
        driver.create(state)
      end
    end

    it 'requests the server' do
      expect(driver).to receive(:orchestration).and_return(orchestration)
      driver.create(state)
    end

    it 'starts the orchestration' do
      expect(orchestration).to receive(:start)
      driver.create(state)
    end

    it 'waits for the orchestration to become ready' do
      expect(driver).to receive(:wait_for_status).with(orchestration, 'ready')
      driver.create(state)
    end

    it 'sets the orchesration ID in the state object' do
      allow(orchestration).to receive(:name_with_container).and_return('orch1')
      driver.create(state)

      expect(state[:orchestration_id]).to eq('orch1')
    end

    context 'when no IP address is available for the server' do
      it 'raises an exception' do
        expect(driver).to receive(:server_ip_address).and_return(nil)
        expect { driver.create(state) }.to raise_error(RuntimeError)
      end
    end

    context 'when an IP address is available' do
      it 'sets it in the state object' do
        expect(driver).to receive(:server_ip_address).and_return('1.2.3.4')
        driver.create(state)
        expect(state[:hostname]).to eq('1.2.3.4')
      end
    end

    it 'waits for the server to be ready' do
      expect(driver).to receive(:wait_for_server).with(state)
      driver.create(state)
    end
  end

  describe '#destroy' do
    let(:state) { { orchestration_id: 'orch1' } }
    let(:orchestration) { double('orchestration') }

    before do
      allow(driver).to receive(:wait_for_status)
      allow(driver).to receive(:orchestration).and_return(orchestration)
      allow(orchestration).to receive(:name_with_container)
      allow(orchestration).to receive(:stop)
      allow(orchestration).to receive(:delete)
    end

    context 'when the orchestration is not in the state object' do
      let(:state) { {} }
      it 'does not attempt to delete the orchestration' do
        expect(driver).not_to receive(:orchestration)
        driver.destroy(state)
      end
    end

    it 'looks up the orchestration by ID' do
      expect(driver).to receive(:orchestration).with('orch1').and_return(orchestration)
      driver.destroy(state)
    end

    it 'does not attempt to stop the orchestration if it cannot be found' do
      allow(driver).to receive(:orchestration).with('orch1').and_raise(OracleCloud::Exception::HTTPNotFound)

      expect(driver).to receive(:warn)
      expect(orchestration).not_to receive(:stop)
      driver.destroy(state)
    end

    it 'stops the orchestration' do
      expect(orchestration).to receive(:stop)
      driver.destroy(state)
    end

    it 'waits for the orchestration to stop' do
      expect(driver).to receive(:wait_for_status).with(orchestration, 'stopped')
      driver.destroy(state)
    end

    it 'deletes the orchestration' do
      expect(orchestration).to receive(:delete)
      driver.destroy(state)
    end
  end

  describe '#oraclecloud_client' do
    it 'returns an OracleCloud::Client instance' do
      expect(driver.oraclecloud_client).to be_an_instance_of(OracleCloud::Client)
    end
  end

  describe '#orchestration' do
    let(:client)         { double('oraclecloud_client') }
    let(:orchestration)  { double('orchestration') }
    let(:orchestrations) { double('orchestrations') }

    before do
      allow(driver).to receive(:oraclecloud_client).and_return(client)
      allow(client).to receive(:orchestrations).and_return(orchestrations)
    end

    context 'when an orchestration has already been created' do
      it 'returns the existing orchestration' do
        driver.instance_variable_set(:@orchestration, '123')
        expect(driver.orchestration).to eq('123')
      end
    end

    context 'when a name is not provided' do
      it 'creates a new orchestration and returns it' do
        allow(driver).to receive(:orchestration_name).and_return('test_orchestration')
        allow(driver).to receive(:description).and_return('test_description')
        allow(driver).to receive(:instance_request).and_return('test_instance')

        expect(orchestrations).to receive(:create).with(name: 'test_orchestration',
                                                        description: 'test_description',
                                                        instances: [ 'test_instance' ])
          .and_return(orchestration)
        expect(driver.orchestration).to eq(orchestration)
      end
    end

    context 'when a name is provided' do
      it 'locates the orchestration and returns it' do
        expect(orchestrations).to receive(:by_name).with('orch1').and_return(orchestration)
        expect(driver.orchestration('orch1')).to eq(orchestration)
      end
    end
  end

  describe '#instance_request' do
    let(:client)           { double('oraclecloud_client') }
    let(:config)           { { shape: 'test_shape', image: 'test_image' } }
    let(:instance_request) { double('instance_request') }
    it 'creates an instance request and returns it' do
      allow(driver).to receive(:oraclecloud_client).and_return(client)
      allow(driver).to receive(:config).and_return(config)
      allow(driver).to receive(:orchestration_name).and_return('test_name')
      allow(driver).to receive(:sshkeys).and_return('test_keys')
      allow(driver).to receive(:public_ip).and_return('test_ip')

      expect(client).to receive(:instance_request).with(name: 'test_name',
                                                        shape: 'test_shape',
                                                        imagelist: 'test_image',
                                                        sshkeys: 'test_keys',
                                                        public_ip: 'test_ip')
        .and_return(instance_request)
      expect(driver.instance_request).to eq(instance_request)
    end
  end

  describe '#server' do
    let(:orchestration) { double('orchestration') }
    let(:instances)     { [ 'server1'] }
    it 'returns the server' do
      allow(driver).to receive(:orchestration).and_return(orchestration)

      expect(orchestration).to receive(:instances).and_return(instances)
      expect(driver.server).to eq('server1')
    end
  end

  describe '#server_ip_address' do
    let(:server) { double('server') }
    it 'returns the private IP address when no public IPs are available' do
      allow(driver).to receive(:server).and_return(server)
      allow(server).to receive(:public_ip_addresses).and_return([])
      allow(server).to receive(:ip_address).and_return('192.168.100.100')

      expect(driver.server_ip_address).to eq('192.168.100.100')
    end

    it 'returns the public IP address if a public IP is available' do
      allow(driver).to receive(:server).and_return(server)
      allow(server).to receive(:public_ip_addresses).and_return([ '1.2.3.4' ])

      expect(driver.server_ip_address).to eq('1.2.3.4')
    end
  end

  describe '#wait_for_server' do
    let(:connection) { instance.transport.connection(state) }
    let(:state)      { {} }

    before do
      allow(transport).to receive(:connection).and_return(connection)
      allow(driver).to receive(:orchestration_name)
    end

    it 'waits for the server to be ready' do
      expect(connection).to receive(:wait_until_ready)
      driver.wait_for_server(state)
    end

    it 'destroys the server and raises an exception if it fails to become ready' do
      allow(connection).to receive(:wait_until_ready).and_raise(Timeout::Error)
      expect(driver).to receive(:destroy).with(state)
      expect { driver.wait_for_server(state) }.to raise_error(Timeout::Error)
    end
  end

  describe '#wait_for_status' do
    let(:item) { double('item') }

    before do
      allow(driver).to receive(:wait_time).and_return(600)
      allow(driver).to receive(:refresh_time).and_return(2)
      allow(item).to receive(:error?)

      # don't actually sleep
      allow(driver).to receive(:sleep)
    end

    context 'when the items completes normally, 3 loops' do
      it 'only refreshes the item 3 times' do
        allow(item).to receive(:status).exactly(3).times.and_return('working', 'working', 'complete')
        expect(item).to receive(:refresh).exactly(3).times

        driver.wait_for_status(item, 'complete')
      end
    end

    context 'when the item is completed on the first loop' do
      it 'only refreshes the item 1 time' do
        allow(item).to receive(:status).once.and_return('complete')
        expect(item).to receive(:refresh).once

        driver.wait_for_status(item, 'complete')
      end
    end

    context 'when the timeout is exceeded' do
      it 'prints a warning and exits' do
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
        expect(driver).to receive(:error)
          .with('Request did not complete in 600 seconds. Check the Oracle Cloud Web UI for more information.')
        expect { driver.wait_for_status(item, 'complete') }.to raise_error(Timeout::Error)
      end
    end

    context 'when a non-timeout exception is raised' do
      it 'raises the original exception' do
        allow(item).to receive(:refresh).and_raise(RuntimeError)
        expect { driver.wait_for_status(item, 'complete') }.to raise_error(RuntimeError)
      end
    end

    context 'when the item errors out' do
      it 'raises an exception' do
        allow(item).to receive(:refresh)
        allow(item).to receive(:status).and_return('error')
        allow(item).to receive(:error?).and_return(true)
        allow(item).to receive(:errors).and_return('test_error')

        expect(driver).to receive(:error).with('Request encountered an error: test_error')
        expect { driver.wait_for_status(item, 'complete') }.to raise_error(RuntimeError)
      end
    end
  end

  describe '#wait_time' do
    it 'returns the correct wait time' do
      allow(driver).to receive(:config).and_return(wait_time: 123)
      expect(driver.wait_time).to eq(123)
    end
  end

  describe '#refresh_time' do
    it 'returns the correct refresh time' do
      allow(driver).to receive(:config).and_return(refresh_time: 123)
      expect(driver.refresh_time).to eq(123)
    end
  end

  describe '#description' do
    let(:instance) { double('instance', name: 'test_instance_name') }
    it 'returns a default description if none is specified in the config' do
      allow(driver).to receive(:config).and_return({})
      allow(driver).to receive(:instance).and_return(instance)
      allow(driver).to receive(:username).and_return('test_username')

      expect(driver.description).to eq('test_instance_name for test_username via Test Kitchen')
    end

    it 'returns the configured description if one is provided' do
      allow(driver).to receive(:config).and_return(description: 'test_description')
      expect(driver.description).to eq('test_description')
    end
  end

  describe '#username' do
    it 'returns the correct username ' do
      allow(driver).to receive(:config).and_return(username: 'test_username')
      expect(driver.username).to eq('test_username')
    end
  end

  describe '#orchestration_name' do
    let(:instance) { double('instance', name: 'test instance') }
    it 'returns a properly formatted name' do
      allow(driver).to receive(:project_name).and_return('testproject')
      allow(driver).to receive(:instance).and_return(instance)

      expect(driver.orchestration_name).to eq('TK-testproject-testinstance')
    end
  end

  describe '#project_name' do
    it 'returns a UUID if a project name has not been configured' do
      allow(driver).to receive(:config).and_return({})

      expect(SecureRandom).to receive(:uuid).and_return('test_uuid')
      expect(driver.project_name).to eq('test_uuid')
    end

    it 'returns the configured project name with spaces stripped' do
      allow(driver).to receive(:config).and_return(project_name: 'my test project')

      expect(driver.project_name).to eq('mytestproject')
    end
  end

  describe '#sshkeys' do
    let(:client) { double('oraclecloud_client') }
    it 'returns an array of formatted keys' do
      allow(driver).to receive(:config).and_return(sshkeys: %w(key1 key2))
      allow(driver).to receive(:oraclecloud_client).and_return(client)
      allow(client).to receive(:compute_identity_domain).and_return('test_domain')

      expect(driver.sshkeys).to eq([ 'test_domain/key1', 'test_domain/key2' ])
    end
  end

  describe '#public_ip' do
    it 'returns nil if no public_ip is configured' do
      allow(driver).to receive(:config).and_return({})
      expect(driver.public_ip).to eq(nil)
    end

    it 'returns :pool if pool is configured' do
      allow(driver).to receive(:config).and_return(public_ip: 'pool')
      expect(driver.public_ip).to eq(:pool)
    end

    it 'returns a reservation name if a non-pool is configured' do
      allow(driver).to receive(:config).and_return(public_ip: 'test_reservation')
      expect(driver.public_ip).to eq('ipreservation:test_reservation')
    end
  end
end
