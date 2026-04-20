require 'mintpress-infrastructure-oci'
require 'yaml'

oci_config = '/opt/opschain/.oci/oci_platform_configs.yaml'
provider_config = OpsChain.dry_run? ? {} : YAML.load_file(oci_config)

environment_name = OpsChain.context.parents.environment.code
common           = OpsChain.properties.common_settings
domain_name      = common.hosts.domain_name
zone             = common.hosts.zone

# OCI platform
infrastructure_oci_oci_platform :oci_platform do
  properties provider_config
  # log_requests true
end

# Chef bootstrapper
infrastructure_chef_bootstrapper :chef_bootstrapper do
  chef_server_url       common.chef.server_url
  knife_config_file     common.chef.knife_config_file
  chef_client_installer common.chef.client_installer
  chef_environment      environment_name
  node_attributes       common.hosts.node_attributes
  run_list              common.hosts.run_list
end

# infrastructure_oci_oci_network_security_group 'test-nsg1' do
#   display_name 'test-nsg1'
#   platform :oci_platform
# end

# infrastructure_chef_bootstrapper :chef_bootstrapper_databases do
#   properties :chef_bootstrapper.properties
#   run_list 'foo'
# end

all_create_steps  = []
all_destroy_steps = []
all_start_steps   = []
all_stop_steps    = []

OpsChain.properties.assets.each do |component_name, component|
  host_create_steps  = []
  host_destroy_steps = []
  host_start_steps   = []
  host_stop_steps    = []

  component.hosts.each do |host|

    host_name = host.name
    short     = host_name.split('.').first

    # Block storage — resource named {hostname}-storage-{suffix} for clarity in OpsChain UI
    block_devices_to_attach = []
    host.storage.each do |str|
      storage_suffix   = str.storage_name.sub("#{host_name}-", '')
      storage_resource = "#{host_name}-storage-#{storage_suffix}"

      infrastructure_oci_oci_storage storage_resource do
        available_actions :create, :attach, :detach, :destroy
        name              str.storage_name
        mount_point       common.storage.mount_point
        storage_name      name
        size_gb           str.size_gb
        platform          :oci_platform
      end

      block_devices_to_attach << storage_resource
    end

    # OCI host — per-host overrides (e.g. memory, cpu, os version) take precedence over common
    vm_name = "#{host_name}-vm"
    infrastructure_oci_oci_host vm_name do
      available_actions        :create, :start, :stop, :restart, :exists?, :destroy
      name                     "#{host_name}#{domain_name}"
      native_instance_type     common.hosts.native_instance_type
      properties                    ({
        'specs.cpu_count': host.respond_to?(:cpu) ? host.cpu : common.hosts.cpu,
        'specs.ram_gb': host.respond_to?(:memory) ? host.memory : common.hosts.memory
      })
      boot_volume_size_in_gbs  common.hosts.boot_volume_size_in_gbs
      operating_system         host.respond_to?(:operating_system)          ? host.operating_system          : common.hosts.operating_system
      operating_system_version host.respond_to?(:operating_system_version)  ? host.operating_system_version  : common.hosts.operating_system_version
      assign_public_ip         common.hosts.assign_public_ip
      keys                     common.hosts.ssh_keys
      # subnet                   common.hosts.subnet
      network_security_groups  common.hosts.network_security_groups
      block_devices            block_devices_to_attach
      always_use_mintpress_bootstrap false
      bootstrap_with_dns       false
      use_flex                 true
      bootstrapper             :chef_bootstrapper
      platform                 :oci_platform
    end

    # Public and private A records
    infrastructure_oci_oci_dns_entry "#{host_name}-public-dns" do
      name     lazy { vm_name.controller.name }
      values   lazy { vm_name.controller.primary_public_ip }
      type     'A'
      zone     zone
      platform :oci_platform
    end

    infrastructure_oci_oci_dns_entry "#{host_name}-private-dns" do
      name     "#{short}-prv#{domain_name}"
      values   lazy { vm_name.controller.primary_ip }
      type     'A'
      zone     zone
      platform :oci_platform
    end

    # VIP CNAME — strips host number suffix (e.g. obpcbpd34obh01 -> obpcbpd34obh)
    if common.hosts.create_cnames
      vip_name = short.sub(/\d+$/, '')
      infrastructure_oci_oci_dns_entry "#{host_name}-vip-cname" do
        name     "#{vip_name}#{domain_name}"
        type     'CNAME'
        values   lazy { vm_name.controller.name }
        zone     zone
        platform :oci_platform
      end
    end

    # SSO CNAMEs — only defined on obpohs
    if host.respond_to?(:sso_cname_list) && host.sso_cname_list
      host.sso_cname_list.each do |sso_cname|
        infrastructure_oci_oci_dns_entry "#{host_name}-#{sso_cname}-cname" do
          name     "#{sso_cname}#{domain_name}"
          type     'CNAME'
          values   lazy { vm_name.controller.name }
          zone     zone
          platform :oci_platform
        end
      end
    end

    # # Wire up Chef bootstrapper at runtime
    # action "#{host_name}-setup-bootstrapper",
    #   description: "Configure Chef bootstrapper for #{host_name}" do
    #   host_obj = vm_name.controller
    #   host_obj.bootstrap_with_dns = false
    #   host_obj.bootstrapper       = :chef_bootstrapper.controller
    # end

    # action "#{host_name}-bootstrap",
    #   description: "Bootstrap #{host_name} with Chef",
    #   steps: [
    #     "#{host_name}-setup-bootstrapper",
    #     "#{vm_name}:bootstrap"
    #   ],
    #   run_as: :sequential

    # Collect all DNS steps for this host
    dns_create_steps = [
      "#{host_name}-public-dns:create",
      "#{host_name}-private-dns:create"
    ]
    dns_create_steps << "#{host_name}-vip-cname:create" if common.hosts.create_cnames
    if host.respond_to?(:sso_cname_list) && host.sso_cname_list
      host.sso_cname_list.each { |s| dns_create_steps << "#{host_name}-#{s}-cname:create" }
    end

    # Individual host: storage -> VM -> DNS
    action "#{host_name}-create",
      description: "Create #{host_name}: storage, VM, DNS and bootstrap",
      steps: [
        *block_devices_to_attach.map { |s| "#{s}:create" },
        "#{vm_name}:create",
        *dns_create_steps
        # "#{host_name}-bootstrap"
      ],
      run_as: :sequential

    action "#{host_name}-destroy",
      description: "Destroy #{host_name} and its storage",
      steps: [
        "#{vm_name}:destroy",
        *block_devices_to_attach.map { |s| "#{s}:destroy" }
      ],
      run_as: :sequential

    action "#{host_name}-start",
      description: "Start #{host_name}",
      steps: ["#{vm_name}:start"],
      run_as: :sequential

    action "#{host_name}-stop",
      description: "Stop #{host_name}",
      steps: ["#{vm_name}:stop"],
      run_as: :sequential

    host_create_steps  << "#{host_name}-create"
    host_destroy_steps << "#{host_name}-destroy"
    host_start_steps   << "#{host_name}-start"
    host_stop_steps    << "#{host_name}-stop"
  end

  # Component-level actions — all hosts in parallel
  action "#{component_name}-create",
    description: "Create all #{component_name} hosts in parallel",
    steps: host_create_steps,
    run_as: :parallel

  action "#{component_name}-destroy",
    description: "Destroy all #{component_name} hosts in parallel",
    steps: host_destroy_steps,
    run_as: :parallel

  action "#{component_name}-start",
    description: "Start all #{component_name} hosts in parallel",
    steps: host_start_steps,
    run_as: :parallel

  action "#{component_name}-stop",
    description: "Stop all #{component_name} hosts in parallel",
    steps: host_stop_steps,
    run_as: :parallel

  all_create_steps  << "#{component_name}-create"
  all_destroy_steps << "#{component_name}-destroy"
  all_start_steps   << "#{component_name}-start"
  all_stop_steps    << "#{component_name}-stop"
end

# Environment-wide actions — sequential to respect OBP dependency order
action "create-all",
  description: "Create all environment infrastructure in dependency order",
  steps: all_create_steps,
  run_as: :sequential

action "destroy-all",
  description: "Destroy all environment infrastructure",
  steps: all_destroy_steps.reverse,
  run_as: :sequential

action "start-all",
  description: "Start all environment infrastructure in dependency order",
  steps: all_start_steps,
  run_as: :sequential

action "stop-all",
  description: "Stop all environment infrastructure",
  steps: all_stop_steps.reverse,
  run_as: :sequential
