require 'tempfile'
require 'base64'
require 'fileutils'
require 'net/ping'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPALL'
return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####

global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge!(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)

if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = 'uploadonly'
end

generic_asset_list = ["#{environment_code}_OBPCID", "#{environment_code}_OBPDOC", "#{environment_code}_OBPIDM", "#{environment_code}_OBPIPM", "#{environment_code}_OBPOAM", "#{environment_code}_OBPOBH", "#{environment_code}_OBPOBU", "#{environment_code}_OBPODI", "#{environment_code}_OBPOID", "#{environment_code}_OBPOIM", "#{environment_code}_OBPOSB", "#{environment_code}_OBPSOA", "#{environment_code}_OBPBIP", "#{environment_code}_OBPCIM"]

# Find the provider from the catalog item
_provider_code = lookup_catalogitem_providerCode(_item_code)


asset_list = []
asset_list.replace(generic_asset_list)

# add otd
asset_list << "#{environment_code}_OBPOTD"

# Now create the dependency list
case
	when mp_action == 'shutdown'
		# Reverse dependency on shutdown
		# Shutdown OID,CID,OTD last
		dependency_list = Hash({"*_*OTD,*_*OID,*_*CID" => "*_*"})
		FIXME
	when mp_action.match('^startup')
		# Always make sure OID, CID and OTD are started before other assets
		dependency_list = Hash({"*_*" => "*_*OTD,*_*OID,*_*CID"})
	else
		# This is mostly when provisioning
		# The following rules have been defined
		# 1. Everything depends on Host, OTD, OID, CID and OAM
		# 2. Host depends on OTD
		# 3. OTD depends on CID, OID, OAM
		# As a result of this dependency, CID, OID and OAM will build first in parallel, OTD next, then Host and then everything else in parallel.
		dependency_list = Hash({"*_*" => "*_*OBH,*_*OTD,*_*OID,*_*CID,*_*OAM", "*_*OBH" => "*_*OTD", "*_*OTD" => "*_*CID,*_*OID,*_*OAM"})
end
Chef::Log.info("---------------- I am running on on-prem and dependency list is #{dependency_list.inspect} ----------------")
Chef::Log.info("---------------- I am running on on-prem and asset list is #{asset_list.inspect} ----------------")


if !asset_list.empty?
	
	mintpress_catalog_action "execute-command-#{mp_action}" do
		asset_list asset_list
		depends dependency_list
		action_to_perform mp_action
		
		# Launch the asset if its not already
		launch_missing true
		
		# Which provider to use
		provider_code _provider_code
		
		# if there is both an item code and a launch description, by default it will match on the launch description.
		# this tells it always match on the item code instead
		prefer_code true
		
		# How many catalogs to fire in one go
		max_parallel 20
		
		# Delay in seconds to fire the catalogs
		request_delay 1
		
		# number of retries in case of failure
		retry_count 2
		
		if mp_action.include?('shutdown')
			ignore_console_state true
			ignore_failure true
			
			# Run irrespective
			always_run true
		end
		
		if mp_action.include?('startup') or mp_action.include?('shutdown')
			ignore_console_state true
			always_run true
		end
		
		console_url node['environmint']['designtime']['server_url']
		console_username node['environmint']['designtime']['username']
		console_password PasswordVault.get_password('mintpress', 'designtime', node['environmint']['designtime']['username'])
	end
	
	
	# Remove the catalog item if action was destroy
	if mp_action == 'destroy'
		
		mintpress_catalog_action "execute-command-remove" do
			asset_list asset_list
			depends dependency_list
			action_to_perform '__remove__'
			
			launch_missing true
			provider_code _provider_code
			prefer_code true
			max_parallel 20
			request_delay 1
			retry_count 2
			ignore_console_state true
			always_run true
			
			console_url node['environmint']['designtime']['server_url']
			console_username node['environmint']['designtime']['username']
			console_password PasswordVault.get_password('mintpress', 'designtime', node['environmint']['designtime']['username'])
			
			# This to get around a bug in Console, when we remove an item, we go back to check if was removed.
			# As of 3.1.6 this is a bug since the orchestration seems to be checking for an item that does not exists (it was removed) and fails with 400 bad request
			# Ignoring the failure since the items are removed from the console.
			# this will get fixed in 3.1.6.+
			ignore_failure true
		end
	
	end
end
