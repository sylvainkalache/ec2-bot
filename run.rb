require 'yaml'
require 'aws-sdk'
require "net/ssh"

# Mount EBS Volume by connecting via SSH
#
# @param [String] ip Server public DNS entry
# @param [String] username User to connect via SSH
# @param [String] mount_directory Where to mount EBS volume
def self.mount_ebs(ip, username = 'ubuntu', mount_directory = '/home/ubuntu/data', ebs_device = '/dev/xvdf')
  Net::SSH.start(ip, username) do |ssh|
    ssh.exec!("mkdir #{mount_directory}")
    ssh.exec!("sudo echo '#{ebs_device} #{mount_directory} ext4 defaults,nofail 0 2' | sudo tee --append /etc/fstab")
    ssh.exec!('sudo mount -a')
  end
end

def self.run
  credentials = YAML.load_file('config.yml')
  Aws.config[:credentials] = Aws::Credentials.new(credentials['access_key_id'], credentials['secret_access_key'])

  client = Aws::EC2::Client.new(region: 'us-east-1')
  resource = Aws::EC2::Resource.new(client: client)

  begin
    instances = resource.create_instances({
                                            :image_id => credentials['image_id'],
                                            :instance_type => credentials['instance_type'],
                                            :min_count => 1,
                                            :max_count => 1,
                                            :security_group_ids => [credentials['security_group_ids']],
                                            :ebs_optimized => false,
                                            :key_name => credentials['key_pair']
                                          })
    instance = instances.first
    instance_id = instances.map(&:id).first
    instance_availability_zone = instance.placement['availability_zone']

    instances.first.create_tags(dry_run: false,
                                resources: instance_id,
                                tags: [{key: "name", value: 'test'}]
                                )

    puts "Launching instance #{instance_id}..."
    client.wait_until(:instance_running, instance_ids: [instance_id])
    puts "instance #{instance_id} available!"

    puts "Creating EBS disk..."
    volume = resource.create_volume(:availability_zone => instance_availability_zone,
                                    :snapshot_id => credentials['snapshot_id']
                                    )
    client.wait_until(:volume_available, volume_ids: [volume.id])
    puts "Volume #{volume.id} available!"

    puts "Attaching volume #{volume.id} to instance #{instance_id}"
    client.attach_volume(
                         dry_run: false,
                         volume_id: volume.id,
                         instance_id: instance_id,
                         device: credentials['ebs_device']
                         )

    puts "Waiting for instance to pass health check"
    client.wait_until(:system_status_ok)

    # That is a long way to get the public dns but the method has a bug
    # https://github.com/aws/aws-sdk-ruby/issues/751
    instance_public_dns = client.describe_instances(instance_ids: [instance_id]).reservations[0].instances[0].public_dns_name

    puts "Instance ready to use :-) connect via #{instance_public_dns}"

    puts "Now mounting the EBS volume"
    mount_ebs(instance_public_dns)
  rescue Aws::EC2::Errors::ServiceError => e
    puts "*** FAILED TO LAUNCH THE INSTANCE ***"
    puts e.message

    # Cleaning behind ourself if necessary
    if instance
      instance.terminate
      instance.wait_until_terminated
    end

    if volume
      volume.delete
    end
  end

end

run()
