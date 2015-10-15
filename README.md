# kitchen-oraclecloud

A driver to allow Test Kitchen to consume Oracle Cloud resources to perform testing.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kitchen-oraclecloud'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install kitchen-oraclecloud

Or even better, install it via ChefDK:

    $ chef gem install kitchen-oraclecloud

## Usage

After installing the gem as described above, edit your .kitchen.yml file to set the driver to 'oraclecloud' and supply your login credentials:

```yaml
driver:
  name: oraclecloud
  username: user@domain.io
  password: mypassword
  identity_domain: oracle12345
  api_url: https://api.cloud.oracle.com
  verify_ssl: true
```

Then configure your platforms. A shape and image is required for each platform:

```yaml
platforms:
  - name: oel64
    driver:
      shape: oc3
      image: /oracle/public/oel_6.4_20GB_x11_RD
  - name: oel66
    driver:
      shape: oc3
      image: /oracle/public/oel_6.6_20GB_x11_RD
```

Other options that you can set include:

 * **sshkeys**: array of Oracle Cloud SSH keys to associate with the instance.
 * **project_name**: optional; descriptive string to be used in the orchestration name, in addition to the Test Kitchen instance name.  If one is not provided, a UUID will be generated.  This helps keep the orchestration names unique but allows you to set something more descriptive for use when displaying all orchestrations in the UI.
 * **description**: optional; override the default description supplied by Test Kitchen
 * **public_ip**: optional; set to `pool` if you want Oracle Cloud to assign an IP from the default pool, or specify an existing IP Reservation name
 * **wait_time**: optional; number of seconds to wait for a server to start.  Defaults to 600.
 * **refresh_time**: optional; number of seconds sleep between checks on whether a server has started.  Defaults to 2.

All of these settings can be set per-platform, as shown above, or can be set globally in the `driver` section of your .kitchen.yml:

```yaml
driver:
  name: oraclecloud
  sshkeys:
    - user1@domain.io/key1
    - user1@domain.io/key2
    - user2@domain.io/user2key
```

### Username

Most Oracle Cloud images use a default username of "opc".  However, Test Kitchen assumes the default user is "root" so you will need to override this in your .kitchen.yml:

```yaml
transport:
  username: opc
```

## License and Authors

Author:: Chef Partner Engineering (<partnereng@chef.io>)

Copyright:: Copyright (c) 2015 Chef Software, Inc.

License:: Apache License, Version 2.0

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the License at

```
http://www.apache.org/licenses/LICENSE-2.0
```

Unless required by applicable law or agreed to in writing, software distributed under the
License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
either express or implied. See the License for the specific language governing permissions
and limitations under the License.

## Contributing

We'd love to hear from you if this doesn't work for you. Please log a GitHub issue, or even better, submit a Pull Request with a fix!

1. Fork it ( https://github.com/chef-partners/kitchen-oraclecloud/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
