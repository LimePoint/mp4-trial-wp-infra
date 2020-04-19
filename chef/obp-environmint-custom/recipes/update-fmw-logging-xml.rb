# Author: Harsha Gurram

# This recipe updates logging.xmls files 
# This can be run over and over again.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

item_code = node.name.split('.')[0][-5..-3].downcase

asset_code = "obp#{item_code}"


if asset_code == 'obpcid'
    asset_code = 'obpcim'
 end

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
logging_xml_path =  "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/config/fmwconfig/servers"

managed_server_list = my_topology_vars["#{asset_code}"].keys.select { |key| key.to_s.match(/_server$/)}
puts "Identified List Of Managed Servers is #{managed_server_list}"
FileUtils.cd("#{logging_xml_path}")
managed_server_list.each do |server_name|
	puts "Updating logging.xmls for servers #{server_name}* "
	Dir.glob("#{server_name}*").each do |managed_server|
		template "Updating Logging XML for #{managed_server} " do
		  source "fmw/logging_xmls/#{asset_code}/#{server_name}_logging.xml.erb"
		  path "#{logging_xml_path}/#{managed_server}/logging.xml"
		  mode '0700'
		end
	end
end


