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

if my_topology_vars['obpidm'].nil?
	generic_asset_list = ["#{environment_code}_OBPCID", "#{environment_code}_OBPDOC", "#{environment_code}_OBPIPM", "#{environment_code}_OBPURM", "#{environment_code}_OBPOAM", "#{environment_code}_OBPOBH", "#{environment_code}_OBPOBU", "#{environment_code}_OBPODI", "#{environment_code}_OBPOID", "#{environment_code}_OBPOIM", "#{environment_code}_OBPOSB", "#{environment_code}_OBPSOA", "#{environment_code}_OBPBIP", "#{environment_code}_OBPCIM"]
else
	generic_asset_list = ["#{environment_code}_OBPCID", "#{environment_code}_OBPDOC", "#{environment_code}_OBPIDM", "#{environment_code}_OBPIPM", "#{environment_code}_OBPURM", "#{environment_code}_OBPOAM", "#{environment_code}_OBPOBH", "#{environment_code}_OBPOBU", "#{environment_code}_OBPODI", "#{environment_code}_OBPOID", "#{environment_code}_OBPOIM", "#{environment_code}_OBPOSB", "#{environment_code}_OBPSOA", "#{environment_code}_OBPBIP", "#{environment_code}_OBPCIM"]
end

include_recipe "::notify-status"

# Ensure we have a trust store password
#PasswordVault.get_password(node.chef_environment, 'all', 'truststorepass' )
include_recipe "::generate-passwords"

# Find the provider from the catalog item
_provider_code = lookup_catalogitem_providerCode(_item_code)

# Figure out what we have to build depending on where we run, cloud vs onprem
# This is the default asset list
# RB: TODO: Get this list from the catalog item
# add database, dataload and deployment
asset_list = []
asset_list.replace(generic_asset_list)
asset_list << "#{environment_code}_OBPDB"

dependency_list={}

# Now create the dependency list
case
	when mp_action=='shutdown'
		# Reverse dependency on shutdown, right side depends on left side
		# Shutdown OID,CID,DB last
		# dependency_list = Hash({"*_OBPDB" => "*_*","*_*OID,*_*CID" => "*_*"})
		dependency_list = Hash({"*_*OID,*_*CID,*_OBPDB" => "*_*", "*_OBPDB" => "*_*OID,*_*CID", })
	when mp_action.match('^startup')
		# DB starts first
		# OID, CID next
		# rest all assets last
		dependency_list = Hash({"*_*" => "*_*OBPDB,*_*OID,*_*CID", "*_*OID" => "*_*OBPDB", "*_*CID" => "*_*OBPDB"})
	when mp_action.match('^destroy')
		dependency_list=Hash({})

		# Remove obpdataload, appdeploy, compdeploy
		# TODO: Find the list of all catalogs here and remove them, Check doco on how to do this

		asset_list << "#{environment_code}_OBPDATALOAD"
		asset_list << "#{environment_code}_OBPAPPDEPLOY"
		asset_list << "#{environment_code}_OBPCOMP"
	when mp_action.match('^provision')
		# This is mostly when provisioning
		# Check what the user selected for app deploy
		if my_topology_vars['obpall']['skip_appdeploy'].nil? or my_topology_vars['obpall']['skip_appdeploy'].to_s == 'false'
			# Add app deploy
			asset_list << "#{environment_code}_OBPAPPDEPLOY"
			Chef::Log.info("---------------- Value of SKIP_APPDEPLOY: #{my_topology_vars['obpall']['skip_appdeploy'].to_s} ----------------")
		else
			Chef::Log.info("---------------- Value of SKIP_APPDEPLOY: #{my_topology_vars['obpall']['skip_appdeploy'].to_s} ----------------")
		end
		dependency_list = Hash({"*_*APPDEPLOY" => "*_*DATALOAD", "*_*DATALOAD" => generic_asset_list.join(',')})
	when mp_action.match(Regexp.new('generatevars|handoverReport'))
		dependency_list=Hash({})
		asset_list = []
	else
		# RB: TODO: Find what to do here --
end

Chef::Log.info("---------------- I am running on OCloud and dependency list is #{dependency_list.inspect} ----------------")
Chef::Log.info("---------------- I am running on OCloud and asset list is #{asset_list.inspect} ----------------")

if mp_action =='provision' or mp_action == 'generatevars'
	# generate Deployment Vars
 	include_recipe "csh-deployments::load_dep_vars"
	# generate the HTML Report
	generateHTMLReport(environment_code, my_topology_vars)
	generatePasswordVaultZips(environment_code, my_topology_vars)

    # Update all DNS records
    global_properties.keys.each do |k|
      if global_properties[k].is_a?(Hash) && global_properties[k].key?('hostnameList')
        global_properties[k]['hostnameList'].each do |h|
          Chef::Log.info("hostname: #{h}")
          host_opts = {}
          host_opts[:hostname] = "#{h}.wpdev.mintpress.io"
          host_opts[:create_cnames] = true
          host_opts[:create_friendly_names] = true
          host_opts[:environment_name] = environment_name
          # Transform hash keys to symbols; no specific reason just personal preference
          host_opts.transform_keys!(&:to_sym)
          oci_host = MintOCIHost.new(host_opts)
          if oci_host.exists?
            oci_host.create_external_dns
            oci_host.create_internal_dns
          end
        end
       end
    end
end

if !asset_list.empty?

	ruby_block "Send Pre-Action Email" do
		block do
			sendEmail(environment_name, 'wpocloud@limepoint.com', 'romil@limepoint.com', "Executing #{mp_action} action on the following assets: #{asset_list}")
		end
	end

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

	ruby_block "Send Post-Action Email" do
		block do
			sendEmail(environment_name, 'wpocloud@limepoint.com', 'romil@limepoint.com', "#{mp_action} action completed successfully on the following assets: #{asset_list}")
		end
	end

	# Remove the catalog item if action was destroy
	if mp_action == 'destroy'

		ruby_block "Send Post-Action Email" do
			block do
				sendEmail(environment_name, 'wpocloud@limepoint.com', 'romil@limepoint.com', "Removing the following catalog instances: #{asset_list}")
			end
		end
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

			ignore_failure true
		end

		ruby_block "Send Post-Action Email" do
			block do
				cleanupVault(environment_code, my_topology_vars)
				sendEmail(environment_name, 'wpocloud@limepoint.com', 'romil@limepoint.com', "Following catalog instances removed successfully: #{asset_list}")
			end
		end
	end

	Chef.event_handler do
		on :run_failed do
			if mp_action == 'destroy'
				puts "In the run failed handler state:"
				# cleanup the password vault
				cleanupVault(environment_code, my_topology_vars)
				sendEmail(environment_name, 'wpocloud@limepoint.com', 'romil@limepoint.com', "Following catalog instances failed to be destroyed: #{asset_list}")

				# This is a hack until https://limepoint.atlassian.net/browse/MINTSD-292 is done
				if ::Dir.exist?("/limepoint/runTime/Repository/baselines/#{environment_code}")
					::FileUtils.remove_dir("/limepoint/runTime/Repository/baselines/#{environment_code}")
				end
			end
			# update the vaults anyways
			if mp_action == 'provision'
				puts "In the run failed handler state:"
				generatePasswordVaultZips(environment_code, my_topology_vars)
			end
		end
		on :run_completed do
			if mp_action == 'provision'
				puts "In the run completed handler state:"
				generatePasswordVaultZips(environment_code, my_topology_vars)
			end
		end

	end
end
