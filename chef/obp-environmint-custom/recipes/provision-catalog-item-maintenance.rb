require 'tempfile'
require 'base64'
require 'net/sftp'
require 'net/ssh'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='MAINTENANCE'
return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')


##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####
#
Chef::Log.info("ENV: #{environment_name}")

global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.merge(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)


asset_list = Array.new

## Construct Asset List based on Input ##
if my_topology_vars.key?'include'

    ['obpcid', 'obpdoc', 'obpipm', 'obpobh', 'obpobu', 'obpodi', 'obpoid', 'obpoim', 'obposb', 'obpsoa', 'obpbip', 'obpcim', 'obpurm', 'obp-banker', 'obp-files', 'obp-reports', 'obp-records', 'obp-worklist', 'obp-sso','obpapi'].each  do |item|
        if my_topology_vars['include'].key?(item) && my_topology_vars['include'][item].downcase == 'true'
            asset_list << "#{item}"
        end
    end
end
Chef::Log.info("ACTIONING  ON ASSETS : #{asset_list}")


otd_host = my_topology_vars['obpotd']['hostnameList'][0]+my_topology_vars['obpotd']['dns_domain_name']

action = node.run_state['mintpress_action']
errmsg = ["Compile Error","Error executing action","ShellCommandFailed","FATAL: Stacktrace dumped"]
ssh_keyfile="/home/mintpress/mintpress/.ssh/id_rsa"
if action=='enable-mm'
  mm_action='enable'
elsif action=='disable-mm'
  mm_action='disable'
end
template "Processing build-params.json" do
  source "default/build-params.json.erb"
  path "/tmp/#{environment_name}_mm-build.json"
  variables(
    :env_name => environment_name,
    :asset_list => asset_list,
    :mm_action => mm_action
  )
  mode '0644'
end

ruby_block "InitiateUpdate" do
  block do
    Chef::Log.info("Transferring Build Params Json to #{otd_host} ..")
    Net::SFTP.start(otd_host, "mintpress", :keys => [ssh_keyfile], :paranoid => Net::SSH::Verifiers::Null.new) do |sftp|
      sftp.upload! "/tmp/#{environment_name}_mm-build.json", "/tmp/#{environment_name}_mm-build.json"
    end
    Chef::Log.info("Successfully Transferred Build Params Json to #{otd_host} ..")
    Chef::Log.info("Start Executing obpotd-update-maintenancemode recipe on target node #{otd_host} ..")
    Net::SSH.start(otd_host, "mintpress", :keys => [ssh_keyfile], :paranoid => Net::SSH::Verifiers::Null.new) do |ssh|
      result = ssh.exec!("sudo -u oracle -- sh -c 'chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::obpotd-update-maintenancemode]' --json-attributes /tmp/#{environment_name}_mm-build.json -l info'")
      puts "#{result}"
      if result.scan(Regexp.union(errmsg)).size > 0
        raise "Fatal error while updating WLS Cert in #{host}"
      else 
       Chef::Log.info("Successfully executed obpotd-update-maintenancemode recipe on target node #{otd_host} ..")
      end
    end
  end
end
