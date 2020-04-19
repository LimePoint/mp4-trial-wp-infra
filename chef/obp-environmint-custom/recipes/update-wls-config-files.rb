# Author: Harsha Gurram

# This recipe updates  adapters.os_xml file of a weblogic domain
# This can be run over and over again.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"
domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']

if ['obpsoa'].include?(asset_code)
	config_file  = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnvSOA.sh"
	ruby_block "Modify setStartupEnvSOA.sh file #{config_file}" do
		block do
		    file = Chef::Util::FileEdit.new(config_file)   
		    file.search_file_replace_line(/CMSParallelRemarkEnabled/, "SERVER_MEM_ARGS_64HotSpot=\"-Xms12g -Xmx12g\"")
		    file.write_file
		end
	end
end
