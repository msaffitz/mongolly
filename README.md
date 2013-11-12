# Mongolly

**Easy backups for EBS-based MongoDB Databases**

Mongolly is a collection of extensions to the [Mongo] Ruby driver and the [Amazon Web Services 
Ruby SDK] that make backing up MongoDB-- even with a complex topology-- as easy as:

`$ mongolly backup`

Mongolly's namesake and patron saint is [Dolly], the world's first cloned Mammal.

[Amazon Web Services Ruby SDK]: http://aws.amazon.com/sdkforruby/
[Mongo]: https://github.com/mongodb/mongo-ruby-driver
[Dolly]: http://en.wikipedia.org/wiki/Dolly_(sheep)

Mongolly is being actively used in production, however as with anything that touches your data or is responsible for something as important as backups, you should review the code and test heavily to make sure that it works properly for you.

### Prerequisites

Mongolly makes the following assumptions about your MongoDB topology:

1. The data files for your database are stored on EBS volumes.
1. Your database or cluster resides within a single AWS region.
1. Your EBS volumes are tagged with an identifier ("mongolly" by default) so that the script can properly backup the right volumes for a given instance.

### Installation

Add this line to your application's Gemfile:

    gem 'mongolly'

And then execute:

    $ bundle install

Or install it yourself:

    $ gem install mongolly

### Usage

The first time you run Mongolly, an empty configuration file will be written to `~/.mongolly`.  You *must* now review this file and add the appropriate configuration for your database.

The configuration options are:

* **database** - db connection string (or for a replica set, array of connection strings).  Example: `localhost:27017`
* **db_username** - db username with administrative privileges
* **db_password** -- db password
* **access_key_id** -- AWS Access Key
* **secret_access_key -- AWS Secret Key
* **region** -- AWS Region where your cluster is located
* **log_level** -- Logging level, `info` by default
* **mongo_start_command** -- The command that's issued on the mongo config server to start the config DB
* **mongo_stop_command** -- The command that's issued on the mongo config server to stop the config DB
* **config_server_ssh_user** -- The use to ssh to the config server as
* **config_server_ssh_keypath** -- The path to the ssh keys
* **volume_tag** -- The tag name identifying volumes to back up.  Default is `mongolly`

Once you have created your configuration file, you are now ready to backup your database.  That's as simple as:

`$ mongolly backup`


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

### Copyright

Copyright (c) 2012-3 Michael Saffitz [@msaffitz](http://www.twitter.com/msaffitz)

See LICENSE.txt for
further details.