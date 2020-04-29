class MintOCIHost

  attr_accessor :configs
  attr_accessor :host_obj
  attr_accessor :custom_boot
  attr_accessor :environment_name
  attr_accessor :default_network_security_groups
  attr_accessor :hostname
  attr_accessor :instance_type
  attr_accessor :operating_system
  attr_accessor :operating_system_version
  attr_accessor :disk_size
  attr_accessor :disk_name
  attr_accessor :mount_name
  attr_accessor :run_list
  attr_accessor :block_devices
  attr_accessor :disable_selinux
  attr_accessor :node_attributes
  attr_accessor :create_cnames
  attr_accessor :create_friendly_names
  attr_accessor :security_rules
  attr_accessor :cname_friendly
  attr_accessor :cname_priv
  attr_accessor :cname_adm

  # init
  def initialize(opts={})
    require 'yaml'
    require 'mintpress-infrastructure-oci'
    require 'mintpress-infrastructure-aws'
    require 'mintpress-dns-powerdns'
    
    self.configs = YAML.load_file("#{ENV['HOME']}/.platform_configs.yaml")
    MintPress::InfrastructureOci::UsingOciPlatform.new(name: 'public_subnet',
      all_platform_services: true,
      fingerprint: self.configs['oci_platform']['fingerprint'],
      key_file: self.configs['oci_platform']['key_file'],
      pass_phrase: self.configs['oci_platform']['pass_phrase'],
      region: self.configs['oci_platform']['region'],
      tenancy: self.configs['oci_platform']['tenancy'],
      compartment: self.configs['oci_platform']['compartment'],
      availability_domain: self.configs['oci_platform']['availability_domain'],
      user: self.configs['oci_platform']['user'],
      subnet_id: self.configs['oci_platform']['subnet_id'],
      assign_public_ip: self.configs['oci_platform']['assign_public_ip'],
      preserve_hostinfo: self.configs['oci_platform']['preserve_hostinfo'],
      admin_connect_user: self.configs['oci_platform']['admin_connect_user'],
      admin_final_user: self.configs['oci_platform']['admin_final_user'],
      keys: [self.configs['oci_platform']['keys']],
      public_key: self.configs['oci_platform']['public_key']
    )
    
    MintPress::InfrastructureAws::UsingAwsPlatform.new(name:'external_dns',
      access_key: self.configs['aws_platform']['access_key'],
      secret_access_key: self.configs['aws_platform']['secret_access_key'],
      region: self.configs['aws_platform']['region']
    )

    MintPress::Infrastructure::UsingPowerDnsEntry.new(name: 'internal_dns_alpha', webserver_host: self.configs['powerdns_platform']['primary_dns'], webserver_port: 80, api_key: self.configs['powerdns_platform']['dns_api_key'])
    
    MintPress::Infrastructure::UsingPowerDnsEntry.new(name: 'internal_dns_omega', webserver_host: self.configs['powerdns_platform']['secondary_dns'], webserver_port: 80, api_key: self.configs['powerdns_platform']['dns_api_key'])

    # Read the security rules that must be applied
    self.security_rules = YAML.load_file("#{__dir__}/../files/security_rules.yaml")

    # Set the default
    self.hostname = opts[:hostname] 
    self.environment_name = opts[:environment_name]
    self.instance_type = opts[:instance_type] || 'VM.Standard.E2.4'
    self.operating_system = opts[:operating_system] || 'Oracle Linux'
    self.operating_system_version = opts[:operating_system_version].to_i || 7
    self.disk_size = opts[:disk_size].to_i || 50
    self.disk_name = opts[:disk_name] || 'oracle'
    self.mount_name = opts[:mount_name] || '/oracle'
    self.run_list = opts[:run_list] || ['oci-bootstrap::default']
    self.block_devices = opts[:block_devices] || nil
    self.disable_selinux = opts[:disable_selinux] || false
    self.node_attributes = opts[:node_attributes] || {}
    self.create_cnames = opts[:create_cnames] || false
    self.create_friendly_names = opts[:create_friendly_names] || false
    if self.create_friendly_names
      short = self.hostname.split(".")[0]
      self.cname_friendly = short.chomp(short[-2..-1]).concat('.wpdev.mintpress.io')
      Chef::Log.info("Setting Friendly Name: #{cname_friendly}")
    end

    if self.create_cnames
      self.cname_priv = self.hostname.split(".")[0].concat('-prv.wpdev.mintpress.io')
      Chef::Log.info("Setting CName: #{cname_priv}")
      short = self.hostname.split(".")[0]
      self.cname_adm = short.chomp(short[-2..-1]).concat('-adm.wpdev.mintpress.io')
      Chef::Log.info("Setting Admin Name: #{cname_adm}")
    end
  end

  # Function to create a host on OCI
  def create

    # Raise if hostname is nil
    raise 'Hostname provided is null. Please provide a valid hostname' if self.hostname.nil?
    raise 'Environment provided is null. Please provide a valid environment' if self.environment_name.nil?

    Chef::Log.info("Setting Hostname: #{hostname}")
    Chef::Log.info("Setting Environment: #{environment_name}")
    Chef::Log.info("Setting Intance Type: #{instance_type}")
    Chef::Log.info("Setting Operating System: #{operating_system}")
    Chef::Log.info("Setting Operating System Version: #{operating_system_version}")
    Chef::Log.info("Setting Run List: #{run_list}")
    Chef::Log.info("Setting Node Attributes: #{node_attributes}")

    self.host_obj = MintPress::Infrastructure::VMHost.new(provider: 'public_subnet', 
      name: self.hostname,
      native_instance_type: self.instance_type,
      operating_system: self.operating_system,
      operating_system_version: self.operating_system_version,
      connect_user: self.configs['oci_platform']['connect_user'],
      final_user: self.configs['oci_platform']['final_user'],
      bootstrap_with_dns: false,
      network_security_groups: 'targets-to-core-services'
    )

    if self.block_devices.nil?
      bd = {name: self.disk_name, mount_point: self.mount_name, size_mb: self.disk_size * 1024 }
      self.host_obj.add_block_device(bd)
      Chef::Log.info("Setting Storage to the default: [#{bd}]")
    else
      block_devices.each do | bd |
        self.host_obj.add_block_device (bd)
      end
      Chef::Log.info("Setting Storage to: [#{block_devices}]")
    end

    ENV['LAS_DISABLE_TRANSFORM']='true'
    # Only create if the host does not exists, this saves us a good amount of roundtrip
    # The risk is that if the host got created and then failed for some reason, the code after the creation won't run which is not good
    # if that happens, destroy and recreate the host or change this logic
    #if ! self.host_obj.exists?
      begin
        create_retry ||= 1
        Chef::Log.info "Attempt [#{create_retry}/3] to create the host."
        self.host_obj.create  
      rescue
        Chef::Log.info "Host Creation failed but will attempt again if retries left"
        retry if (create_retry += 1) < 4
      end
      #self.host_obj.transport.execute("systemctl stop firewalld; services firewalld stop")
      if self.disable_selinux
        restart_required = true
        # Disable SELinux
        se_status = self.host_obj.transport.execute('sestatus')
        if se_status.stdout.include?('disabled')
          restart_required = false
        else
          Chef::Log.info ('Disabling SELinux')
          selnx = MintPress::Resources::FileUtils.new(host: self.host_obj, file: '/etc/selinux/config', pattern: 'FOO', line: 'BAR')
          selnx.pattern = "^SELINUX=.*"
          selnx.line = 'SELINUX=disabled'
          selnx.replace_lines
          restart_required = true
        end
        # reboot for setting to take effect
        if restart_required
          self.host_obj.restart
        end
      end
    #end

    # Enforce the default security rules
    add_default_security_rules

    # Create the External DNS Entry
    create_external_dns

    # Create the Internal DNS Entry
    create_internal_dns

    # This ensures we can bootstrap to the chef server, the problem is that the VM
    # does not knows about the chef server, using an IP is not an option because curl errors out with 'curl: (35) Peer reports it experienced an internal error.'
    # So, what we are doing is, adding a temporary entry in the /etc/hosts of the VM if we don't find /etc/chef/client.rb
    # Because if /etc/chef/client.rb exists, that means the node is already bootstrapped and we don't have to hack the host entry
    hosts_file_updated = false
    mint_host=`hostname`.strip
    mint_ip=`host #{mint_host}| cut -d' ' -f4`.strip
    if self.host_obj.transport.File.exist?('/etc/chef/client.rb')
        Chef::Log.info ('/etc/chef/client.rb already exists, no need to update the hosts file.')
    else
        Chef::Log.info ('/etc/chef/client.rb does not exists. Temporarily updating the /etc/hosts file with MintPress Entry.')
        h_file = MintPress::Resources::FileUtils.new(host: self.host_obj, file: '/etc/hosts', pattern: 'FOO', line: 'BAR')
        h_file.pattern = "^#{mint_ip}.*"
        h_file.line = "#{mint_ip} #{mint_host}"
        h_file.replace_or_add_lines
        hosts_file_updated = true
    end
  
    # We should remove the host entry even if bootstrap fails 
    begin 
      # Now Bootstrap
      self.host_obj.bootstrapper = MintPress::Infrastructure::UsingChefBootstrapper.new(chef_environment: self.environment_name, omnibus_url: "https://#{mint_host}/staticfiles/install-chef.sh", run_list: run_list, node_attributes: self.node_attributes)
      self.host_obj.bootstrap
    ensure
      # Remove the hosts file change if we introduced it
      if hosts_file_updated
        Chef::Log.info ('Removing the temporary update from /etc/hosts')
        h_file = MintPress::Resources::FileUtils.new(host: self.host_obj, file: '/etc/hosts', pattern: 'FOO', line: 'BAR')
        h_file.pattern = "^#{mint_ip}.*"
        h_file.delete_lines
      end
    end
  end


  # Method to add default rules
  def add_default_security_rules
    raise 'Hostname provided is null. Please provide a valid hostname' if self.hostname.nil?
    raise 'Host Object is null. Please provide a valid host object' if self.host_obj.nil?

    if !security_rules['security_rules'].nil?
      rules = security_rules['security_rules']
      # First all the default security rules
      rules['default'].each do |secrule|
        Chef::Log.info "Adding Security rule: [#{secrule['name']}]"
        host_obj.add_network_security_group_by_display_name(secrule['name'])
      end
      
      # If env is typical workload add typical work load rules
      # TODO - Make this efficient, this is shite
      if self.environment_name.match(/^bpd/) or environment_name.match(/^eng/) or environment_name.match(/^shared-services/) or environment_name.match(/^och/)
        rules['bpd_workload'].each do |secrule|
          Chef::Log.info "Adding Security rule: [#{secrule['name']}]"
          host_obj.add_network_security_group_by_display_name(secrule['name'])
        end
      end
    
      # If env is a core service
      if self.environment_name.match(/^core-services/) 
        rules['tools_workload'].each do |secrule|
          Chef::Log.info "Adding Security rule: [#{secrule['name']}]"
          host_obj.add_network_security_group_by_display_name(secrule['name'])
        end
      end

      # Special case for stage and MintPress servers (although mintpress is put in manually
      if host_obj.hostname == 'stage.wpdev.mintpress.io'
        rules['privileged_workload'].each do |secrule|
          Chef::Log.info "Adding Security rule: [#{secrule['name']}]"
          host_obj.add_network_security_group_by_display_name(secrule['name'])
        end
      end
      host_obj.update
    else
      Chef::Log.info ("Security rules is empty, I can make the VM but it's gonna be useless so I refuse to build it. Fix the security list file and retry. ")
      raise
    end
  end

  # Method to delete the host
  def destroy
    # Raise if hostname is nil
    raise 'Hostname provided is null. Please provide a valid hostname' if self.hostname.nil?
    
    ENV['LAS_DISABLE_TRANSFORM']='true'
    self.host_obj = MintPress::Infrastructure::VMHost.new(provider: 'public_subnet', 
      name: self.hostname
    )

    if self.host_obj.exists?
      Chef::Log.info("Host: [#{hostname}] found. Destroying.")
      # Tell our code that we bootstrapped it with Chef so we need to get rid of it from chef
      self.host_obj.bootstrapper = MintPress::Infrastructure::UsingChefBootstrapper.new(chef_environment: self.environment_name)
      self.host_obj.destroy

      # Destroy the external DNS
      destroy_external_dns

      # Destroy the Internal DNS Entry
      destroy_internal_dns
    else
      Chef::Log.info("Host: [#{hostname}] not found. Skipping delete.")
    end
  end

  # Create the internal DNS entry, this will create entries in both internal DNSes
  def create_internal_dns
    raise 'Hostname does not exists' if self.host_obj.nil?
    Chef::Log.info 'Publishing DNS Record to Internal DNS Alpha'
    d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'A', name: self.host_obj.name, values: self.host_obj.primary_ip, ttl: 300)
    d_record.create
    # Create the entry in secondory instance
    Chef::Log.info 'Publishing DNS Record to Internal DNS Omega'
    d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'A', name: self.host_obj.name, values: self.host_obj.primary_ip, ttl: 300)
    d_record.create


    # Create CNAMES if required
    if self.create_cnames
      Chef::Log.info 'Publishing DNS CNAME Record to Internal DNS Alpha'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'CNAME', name: cname_priv, values: self.host_obj.name, ttl: 300)
      d_record.create
      
      # Create the entry in secondory instance
      Chef::Log.info 'Publishing DNS CNAME Record to Internal DNS Omega'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'CNAME', name: cname_priv, values: self.host_obj.name, ttl: 300)
      d_record.create

      # Add -adm Entries
      Chef::Log.info 'Publishing DNS Admin Record to Internal DNS Alpha'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'CNAME', name: cname_adm, values: self.host_obj.name, ttl: 300)
      d_record.create
      
      # Create the entry in secondory instance
      Chef::Log.info 'Publishing DNS Admin Record to Internal DNS Omega'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'CNAME', name: cname_adm, values: self.host_obj.name, ttl: 300)
      d_record.create
    end

    if self.create_friendly_names
      Chef::Log.info 'Publishing DNS Friendly CNAME Record to Internal DNS Alpha'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'CNAME', name: cname_friendly, values: self.host_obj.name, ttl: 300)
      d_record.create

      Chef::Log.info 'Publishing DNS Friendly CNAME Record to Internal DNS Omega'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'CNAME', name: cname_friendly, values: self.host_obj.name, ttl: 300)
      d_record.create
    end
  end
 
  # Remove the internal DNS entry, this will remove entries in both internal DNSes
  def destroy_internal_dns
    raise 'Hostname does not exists' if self.host_obj.nil?
    Chef::Log.info 'Unpublishing DNS Record from Internal DNS Alpha'
    d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'A', name: self.host_obj.name, values: self.host_obj.primary_ip, ttl: 300)
    d_record.remove
    # Delete the entry in secondory instance
    Chef::Log.info 'Unpublishing DNS Record from Internal DNS Omega'
    d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'A', name: self.host_obj.name, values: self.host_obj.primary_ip, ttl: 300)
    d_record.remove

    # Destroy CNAMES if required
    if self.create_cnames
      Chef::Log.info 'UnPublishing DNS CNAME Record to Internal DNS Alpha'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'CNAME', name: cname_priv, values: self.host_obj.name, ttl: 300)
      d_record.remove
      
      # Delete the entry in secondory instance
      Chef::Log.info 'Publishing DNS CNAME Record to Internal DNS Omega'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'CNAME', name: cname_priv, values: self.host_obj.name, ttl: 300)
      d_record.remove

      # Remove the -adm
      Chef::Log.info 'UnPublishing DNS Admin Record to Internal DNS Alpha'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'CNAME', name: cname_adm, values: self.host_obj.name, ttl: 300)
      d_record.remove
      
      Chef::Log.info 'Publishing DNS Admin Record to Internal DNS Omega'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'CNAME', name: cname_adm, values: self.host_obj.name, ttl: 300)
      d_record.remove
    end

    if self.create_friendly_names
      Chef::Log.info 'Unpublishing DNS Friendly CNAME Record to Internal DNS Alpha'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_alpha', type: 'CNAME', name: cname_friendly, values: self.host_obj.name, ttl: 300)
      d_record.remove

      Chef::Log.info 'Unpublishing DNS Friendly CNAME Record to Internal DNS Omega'
      d_record = MintPress::Infrastructure::PowerDnsEntry.new(provider: 'internal_dns_omega', type: 'CNAME', name: cname_friendly, values: self.host_obj.name, ttl: 300)
      d_record.remove
    end
  end

  # Create the external DNS entry 
  def create_external_dns
    raise 'Hostname does not exists' if self.host_obj.nil?
    Chef::Log.info 'Publishing DNS Record to External DNS'
    d_record =  MintPress::InfrastructureAws::Route53DnsEntry.new(ttl: 300, type: 'A', name: self.host_obj.name, values: self.host_obj.primary_public_ip, hosted_zone_name: self.configs['aws_platform']['dns_zone'], region: self.configs['aws_platform']['region'])
    d_record.create
    
    if self.create_friendly_names
      Chef::Log.info 'Publishing DNS Friendly CNAME Record to External DNS'
      d_record =  MintPress::InfrastructureAws::Route53DnsEntry.new(ttl: 300, type: 'CNAME', name: cname_friendly, values: self.host_obj.name, hosted_zone_name: self.configs['aws_platform']['dns_zone'], region: self.configs['aws_platform']['region'])
      d_record.create
    end
    if self.create_cnames
      # Add -adm Entries
      Chef::Log.info 'Publishing DNS Admin Record to External DNS'
      d_record =  MintPress::InfrastructureAws::Route53DnsEntry.new(ttl: 300, type: 'CNAME', name: cname_adm, values: self.host_obj.name, hosted_zone_name: self.configs['aws_platform']['dns_zone'], region: self.configs['aws_platform']['region'])
      d_record.create
    end
  end

  # Destroy the external DNS entry
  def destroy_external_dns
    raise 'Hostname does not exists' if self.host_obj.nil?
    Chef::Log.info 'Unpublishing DNS Record from External DNS'
    d_record =  MintPress::InfrastructureAws::Route53DnsEntry.new(ttl: 300, type: 'A', name: self.host_obj.name, values: self.host_obj.primary_public_ip, hosted_zone_name: self.configs['aws_platform']['dns_zone'], region: self.configs['aws_platform']['region'])
    d_record.remove

    if self.create_friendly_names
      Chef::Log.info 'Unpublishing DNS Friendly CNAME Record from External DNS'
      d_record =  MintPress::InfrastructureAws::Route53DnsEntry.new(ttl: 300, type: 'CNAME', name: cname_friendly, values: self.host_obj.name, hosted_zone_name: self.configs['aws_platform']['dns_zone'], region: self.configs['aws_platform']['region'])
      d_record.remove
    end
    if self.create_cnames
      # Remove -adm Entries
      Chef::Log.info 'Unpublishing DNS Admin Record to External DNS'
      d_record =  MintPress::InfrastructureAws::Route53DnsEntry.new(ttl: 300, type: 'CNAME', name: cname_adm, values: self.host_obj.name, hosted_zone_name: self.configs['aws_platform']['dns_zone'], region: self.configs['aws_platform']['region'])
      d_record.remove
    end
  end
end
