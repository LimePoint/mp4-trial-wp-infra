Bundler.require

require 'mintpress-infrastructure-oci'
# actions for vms

# hostname:create # create individual host
# obpotd-create # create all hosts in parallel for otd
# cix1-create # create all assets in parallel which in turn create all hosts in parallel

# if there's shared_storage

oci_test_config = '/opt/opschain/oci_platform_configs.yaml' # this will come from vault from projects settings

if OpsChain.dry_run?
  provider_config = {}
else
  provider_config = YAML.load_file(oci_test_config)
end

infrastructure_oci_oci_platform :oci_test_platform do
  properties provider_config
end

# Define resource by passing individual properties
infrastructure_chef_bootstrapper "default_bootstrapper" do
  chef_server_url 'https://mintpress.trial.limepoint.com:8443/organizations/environmint'
  chef_client_installer '/lib/cinc-client/cinc-client.rpm'
  knife_config_file '/opt/mintpress/.cinc/knife.rb'
  chef_environment 'environmint-provisioning'
  run_list OpsChain.properties.common_settings.hosts.run_list
end

# Define resource by consuming properties of other resources
# Override properties using merge
infrastructure_chef_bootstrapper "otd_bootstrapper" do
  properties default_bootstrapper.properties.merge(run_list: OpsChain.properties.assets.obpotd.run_list)
end

# Get common host properties
common_host_properties = OpsChain.properties.common_settings.hosts.merge(
  'specs.cpu_count': OpsChain.properties.common_settings.hosts.cpu,
  'specs.ram_gb': OpsChain.properties.common_settings.hosts.memory
)

# Make list of all hosts
all_hosts = []
OpsChain.properties.assets.each do | asset_name, deets |
  deets.hosts.each do | host |
    infrastructure_oci_oci_host host.name do
      available_actions :create, :start, :stop, :restart, :exists?, :destroy # only to show ui, else we can all any action
      properties common_host_properties

      name "#{host.name}#{OpsChain.properties.common_settings.domain_name}"
      platform oci_test_platform
    end

    # Every host gets a default storage 
    infrastructure_oci_oci_storage "#{host.name}-storage" do
      available_actions :create, :attach, :detach, :destroy
 
      properties OpsChain.properties.common_settings.storage
      host [host.name]
    end
    all_hosts << host.name
  end

  # Now see if there's shared storage and create resources for those.
  deets.shared_storage.each do | st |
    infrastructure_oci_oci_shared_storage st.storage_name do
      available_actions :create, :attach, :setup_ocfs, :detach, :destroy
      properties OpsChain.properties.common_settings.shared_storage
      storage_name st.storage_name
      host st.hosts
      cluster_name st.cluster_name

      # Only methods in MintSDK classes are exposed as action by default
      # if there's any method that takes an argument, we have to attach it explicitly
      action :attach do |ac|
        ac.controller.attach
      end

      action :detach do |ac|
        ac.controller.detach
      end
    end
  end
end


# make a string of the actions that we are interested in
# this will be used later when creating asset based actions
host_actions = {}
%w(create start stop restart exists? destroy).each do |action_name|
  host_actions[action_name] = all_hosts.map { |h| "#{h}:#{action_name}" }
end

# this block will create actions like obpotd-create
asset_actions = []
OpsChain.properties.assets.each do | asset_name, deets |
  %w(create start stop restart exists? destroy).each do |act|
    action "#{asset_name}-#{act}", steps: host_actions[act].select { |ha| ha.match?(/#{asset_name}/)}, run_as: :parallel, description: "----- #{asset_name}-#{act}"
    asset_actions << "#{asset_name}-#{act}"
  end
end

# this block will create actions like cix1-create
%w(create start stop restart exists? destroy).each do |act|
  action "allvms-#{act}", steps: asset_actions.select { |ha| ha.match?(/#{act}/)}, run_as: :parallel
end