# Author: Harsha Gurram,

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

base_dir = "/oracle/app/binaries/#{asset_code}/tmp"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"

template "Processing jms-queue-sec-pol.py" do
	source "fmw/wlst/jms-queue-sec-pol.py.erb"
	path "#{base_dir}/jms-queue-sec-pol.py"
	variables(
		:JMSModule => "OCHJMSModule",
		:JMSQueue => "OCHPublishRequestQ",
		:UserName => "SA_OCH_OBP_MANAGE_USER"
	)
	mode '0644'
	user 'oracle'
	group 'oinstall'
end	

bash 'Executing jms-queue-sec-pol.py' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{base_dir}/jms-queue-sec-pol.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
end