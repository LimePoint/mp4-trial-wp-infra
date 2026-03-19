  require 'mintpress-infrastructure-oci'
  # require 'mintpress-dns-powerdns'
  require_relative 'utility'

  oci_config = '/opt/opschain/oci_platform_configs.yaml' # this will come from vault from projects settings
  if OpsChain.dry_run?
    provider_config = {}
  else
    provider_config = YAML.load_file(oci_config)
  end

  environment_name = OpsChain.context.parents.environment.code
  domain_name = OpsChain.properties.common_settings.hosts.domain_name
  create_cnames = OpsChain.properties.common_settings.hosts.create_cnames
  create_friendly_names = OpsChain.properties.common_settings.hosts.create_friendly_names
  zone = OpsChain.properties.common_settings.hosts.zone

  common_host_properties = OpsChain.properties.common_settings.hosts
  common_storage_properties = OpsChain.properties.common_settings.storage

  if common_host_properties.native_instance_type.include? 'Flex'
    common_host_properties = common_host_properties.merge(
        'use_flex': true,
        'specs.cpu_count': OpsChain.properties.common_settings.hosts.cpu,
        'specs.ram_gb': OpsChain.properties.common_settings.hosts.memory
    )
  end

  infrastructure_oci_oci_platform :oci_test_platform do
    # properties YAML.load_file(oci_config)
    # properties lazy { YAML.load_file('/opt/opschain/oci_platform_configs1.yaml') }
    # properties lazy { provider_config }
    properties provider_config
    log_requests true
    identity_region 'AU'
    # assign_public_ip provider_config['oci_platform']['assign_public_ip'] #NOTE
  end


   #chef-bootstrapper
  infrastructure_chef_bootstrapper "chef" do
    chef_server_url 'https://mintpress-dm-primary.trial.limepoint.com:8443/organizations/environmint'
    chef_client_installer '/lib/cinc-client/cinc-client.rpm'
    knife_config_file '/opt/opschain/.cinc/knife.rb'
    chef_environment environment_name
    node_attributes OpsChain.properties.common_settings.hosts.node_attributes
    run_list OpsChain.properties.common_settings.hosts.run_list
  end

  # security_rules
  security_rules = YAML.load_file("#{__dir__}/oci-common/files/security_rules.yaml")
  raise "Security rules is empty, I can make the VM but it's gonna be useless so I refuse to build it. Fix the security list file and retry. " if security_rules['security_rules'].nil?
  sec_rules = []
  rules = security_rules['security_rules']
  rules['all'][0]['name'].each do | secrule |
    infrastructure_oci_oci_network_security_group secrule do
      display_name secrule
      platform oci_test_platform
    end
    sec_rules  << secrule
  end

  security_rules_actions = {}
  %w(create get_display_name get_my_ocid get_vcn exists? remove).each do |action_name|
    security_rules_actions[action_name] = sec_rules.map { |h| "#{h}:#{action_name}" }
  end

  %w(create remove).each do |act|
    action "security-rules-#{act}", steps: security_rules_actions[act].select { |ha| ha }, run_as: :parallel, description: "security-rules-#{act}"
  end

  # Make list of all hosts and shared storage
  all_hosts = []
  a_dns_entries = []
  cname_dns_entries = []

  OpsChain.properties.assets.each do | asset_name, deets |
    deets.hosts.each do | host |
      short          = host.name.split(".")[0]
      cname_friendly = short.chomp(short[-2..-1]).concat(domain_name)
      cname_adm      = short.chomp(short[-2..-1]).concat('-adm').concat(domain_name)
      cname_priv     = short.concat('-prv').concat(domain_name)

      if host.sso_cname_list
        create_sso_cnames = true
        sso_cnames = host.sso_cname_list
      end

      # Every host gets a default storage, storage shd be defined earlier if required to attach host
      block_devices_to_attach = []
      host.storage.each do | str |
        infrastructure_oci_oci_storage str.storage_name do
          available_actions :create, :attach, :detach, :destroy

          properties common_storage_properties.merge(str)
          name str.storage_name # this is required bcoz of the DSL reference
          storage_name name
          platform oci_test_platform
        end
        block_devices_to_attach << str.storage_name
      end


      infrastructure_oci_oci_host host.name do
        available_actions :create, :start, :stop, :restart, :exists?, :destroy # only to show ui, else we can all any action
        # action_policies ignore_defined: true#, ignore_failure: true
        name "#{host.name}#{domain_name}"
        properties common_host_properties
        always_use_mintpress_bootstrap false
        bootstrap_with_dns false
        network_security_groups security_rules['security_rules']['default'][0]['name']
        # admin_final_user#NOTE

        platform oci_test_platform
        block_devices block_devices_to_attach
      end
      all_hosts << host.name

      # OCI
      # create public/private A dns_entries
      ["public", "private"].each do |type|
        infrastructure_oci_oci_dns_entry "#{host.name}-#{type}-a-dns" do
          if type == "public"
            name   lazy { ref(host.name).controller.name } #NOTE
             values lazy { ref(host.name).controller.primary_public_ip }#NOTE
          else
            name   "#{cname_priv}"
            values lazy { ref(host.name).controller.primary_ip }
          end
          type     'A'
          zone     zone
          platform oci_test_platform
        end
      end
      a_dns_entries << "#{host.name}-public-a-dns" << "#{host.name}-private-a-dns"

      # construct hash to assit with iterative construction of infrastructure_oci_oci_dns_entry
      active_cnames = {}
      if create_cnames
        active_cnames["cname-dns"] = cname_friendly
      end
      if create_sso_cnames
        sso_cnames.each do |sso_cname|
          active_cnames["sso-#{sso_cname}-cname-dns"] = "#{sso_cname}#{domain_name}"
        end
      end
      active_cnames.each do |suffix, cname_value|
        resource_name = "#{host.name}-#{suffix}"

        infrastructure_oci_oci_dns_entry resource_name do
          name     "#{cname_value}"
          type     'CNAME'
          values   lazy { ref(host.name).controller.name }
          zone     zone
          platform oci_test_platform
        end

        cname_dns_entries << resource_name
      end

      ## power dns A entries
      #dns_targets = {
      #    "alpha" => "primary_dns",
      #    "omega" => "secondary_dns"
      #}
      #dns_targets.each do |suffix, config_key|
      #  infrastructure_power_dns_entry "#{host.name}_#{suffix}" do
      #    # ArgumentError: Attribute :name on MintPress::Infrastructure::PowerDnsEntry must be of type [String],
      #    # however you specified a MintPress::InfrastructureOci::OCIHost (#<MintPress::InfrastructureOci::OCIHost:0x00007ff71492fd20>)) (ArgumentError)
      #    name host.name
      #    # name literal { host.name }#NOTE
      #    #webserver_host provider_config['powerdns_platform'][config_key]
      #    #webserver_port 80
      #    #api_key        provider_config['powerdns_platform']['dns_api_key']
      #    type           'A'
      #    values         lazy { ref(host.name).controller.primary_ip }
      #  end
      #    # a_dns_entries << "#{host.name}_#{suffix}" # TODO: Enable for powerdns
      #end
      #
      #cname_types = {}
      #if create_cnames
      #  cname_types.merge!({"private" => cname_priv, "admin"   => cname_adm})
      #end
      #if create_friendly_names
      #  cname_types.merge!({"friendly" => cname_friendly})
      #end
      #
      #if create_sso_cnames
      #  sso_cnames.each do |sso_cname|
      #    cname_types["sso-#{sso_cname}"] = "#{sso_cname}#{domain_name}"
      #  end
      #end
      #cname_types.each do |type_label, cname_prefix|
      #  dns_targets.each do |suffix, config_key|
      #
      #    infrastructure_power_dns_entry "#{host.name}-power-dns-#{type_label}-cname-#{suffix}" do
      #      name           "#{cname_prefix}"
      #      #webserver_host provider_config['powerdns_platform'][config_key]
      #      #webserver_port 80
      #      #api_key        provider_config['powerdns_platform']['dns_api_key']
      #      type           'CNAME'
      #      values         lazy { ref(host.name).controller.name }
      #    end
      #      # cname_dns_entries << "#{host.name}-power-dns-#{type_label}-cname-#{suffix}" # TODO: Enable for powerdns
      #  end
      #end


      # support for bootstrap
      resources_execute "#{host.name}-whoami" do
        name "whoami"
        host host.name
      end

      #NOTE
      # we can use oci_host.disable_se_linux without having to use resources_file_utils
      # however, there is no way to control invocation of cix1obpotd01:disable_se_linux based on a property?
      if common_host_properties.disable_selinux
        resources_file_utils "#{host.name}-disable_se_linux" do
          host host.name
          file '/etc/selinux/config'
          pattern '^SELINUX=.*'
          line 'SELINUX=disabled # updated by script'
          as_admin true
        end

        action "#{host.name}-disable_selinux", description: "#{host.name}-disable_selinux" do
          se_enabled = ref(host.name).controller.transport&.execute('sestatus')&.stdout&.include?('enabled')
          if se_enabled
            OpsChain.append_child_steps(%I[#{host.name}-disable_se_linux:replace_lines #{host.name}:restart])#NOTE
          end
        end

      else
        # empty action to support  in child steps
        action "#{host.name}-disable_selinux", description: "#{host.name}-disable_selinux" do
        end
      end

      resources_file_utils "#{host.name}_add_mintpress_hosts_entry" do
        host host.name
        file '/etc/hosts'
        pattern lazy { ref(host.name).controller.primary_public_ip }
        line lazy { "#{ref(host.name).controller.primary_public_ip} #{host.name.controller.name}" }
        as_admin true
      end

      action "#{host.name}-add-mintpress-hosts-entry", description: "#{host.name}-add-mintpress-hosts-entry" do
        mint_ip = ref(host.name).controller.primary_public_ip
        host_entry_added = ref(host.name).controller.transport&.execute('cat /etc/hosts')&.stdout&.include?("#{mint_ip}")
        unless host_entry_added
          OpsChain.append_child_steps(%I[#{host.name}_add_mintpress_hosts_entry:replace_or_add_lines])
        end
      end

      action "#{host.name}-setup-bootstrapper" do

        host_obj = ref(host.name).controller
        host_obj.bootstrap_with_dns = false if host_obj.bootstrap_with_dns
        host_obj.bootstrapper = ref('chef').controller
      end
      action "#{host.name}:bootstrap": ["#{host.name}-setup-bootstrapper"]
      action "#{host.name}:unbootstrap": ["#{host.name}-setup-bootstrapper"]

      resources_file_utils "#{host.name}_remove_mintpress_hosts_entry" do
        host host.name
        file '/etc/hosts'
        pattern lazy { ref(host.name).controller.primary_public_ip }
        line 'BAR'
        as_admin true
      end

      action "#{host.name}-remove-mintpress-hosts-entry", description: "#{host.name}-remove-mintpress-hosts-entry" do
          OpsChain.append_child_steps(%I[#{host.name}_remove_mintpress_hosts_entry:delete_lines])
      end

      #action "#{host.name}-bootstrap", description: "#{host.name}-bootstrap" do
      #  OpsChain.append_child_steps(%I[
      #    #{host.name}-whoami:execute
      #    #{host.name}-disable_selinux
      #    #{host.name}-add-mintpress-hosts-entry
      #    #{host.name}:bootstrap
      #    #{host.name}-remove-mintpress-hosts-entry
      #    ])
      #end

      bootstrap_steps = [
            "#{host.name}-whoami:execute",
            (common_host_properties.disable_selinux ? "#{host.name}:disable_se_linux" : nil),
            "#{host.name}-add-mintpress-hosts-entry",
            "#{host.name}:bootstrap",
            "#{host.name}-remove-mintpress-hosts-entry"
        ].compact

      action "#{host.name}-bootstrap", description: "#{host.name}-bootstrap", steps: bootstrap_steps

      # security rules update on infrastructure_oci_oci_host host.name

      action "#{host.name}-setup-security-rules" do
        host_obj = ref(host.name).controller

        update_security_rules(host_obj, rules['default'][0]['name'])

        if environment_name.match(/\b^(bpd|eng|och|shared-services|tas)/)
          update_security_rules(host_obj, rules['bpd_workload'][0]['name'])
        end
        if environment_name.match(/^core-services/)
          update_security_rules(host_obj, rules['tools_workload'][0]['name'])
        end
        if host.name.match(/\b^(stage|mintpress.*)\b/)
          update_security_rules(host_obj, rules['privileged_workload'][0]['name'])
        end

      end
      action "#{host.name}-update-security-rules": ["#{host.name}-setup-security-rules"], steps:["#{host.name}:update"]
    end
  end

  require_relative 'overlay-actions'
  overlay_actions(all_hosts, a_dns_entries, cname_dns_entries)