# Author: Chinmoy Rath,

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

# Recipe to provide JMS Queue Access

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

if my_topology_vars["#{asset_code}"]['dns_domain_name'] != '.wpdev.mintpress.io' && !['svp3r','prd3r','psp3'].include?(environment_name) && ['obpoid','obpcid'].include?(asset_code)
  if asset_code == 'obpoid'
    asset_code = 'obpoim'
  end
  if asset_code == 'obpcid'
    asset_code = 'obpcim'
  end
end

base_dir = "/oracle/app/binaries/#{asset_code}/tmp"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17101"

template "Processing updateJDBCDriver.py" do
	source "fmw/wlst/updateJDBCDriver.py.erb"
	path "#{base_dir}/updateJDBCDriver.py"
	mode '0644'
	user 'oracle'
	group 'oinstall'
end	

bash 'Executing updateJDBCDriver.py' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{base_dir}/updateJDBCDriver.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
end