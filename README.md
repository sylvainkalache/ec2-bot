# What is that for?
Simple script to launch an instance an attach an EBS volume to it that is created from a snapshot and mount it on the instance.

# Requirements

* Ruby (tested under v2.1.2)
* Bundler
* aws-sdk v2
* SSH key pair that is configured with AWS
* 5 minutes of your time

# How to use

* run `bundle install`
* create a config.yml file `cp config-example.yml config.yml`
* fill config.yml with the right values
* make sure that you ssh client will use the private key you specified (via conf file or use `ssh-add path_to_private_key`)
* run it! `bundle exec ruby run.rb`
* enjoy :)