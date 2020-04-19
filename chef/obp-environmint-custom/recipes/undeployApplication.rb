# Author: Harsha Gurram

# This recipe updates  ODL Log Levels to ERROR:1 in assets - OSB,OBH,OBU,SOA
# This can be run over and over again.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

item_code = node.name.split('.')[0][-5..-3].downcase

asset_code = "obp#{item_code}"
domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"

Chef::Log.info('Connecting to domain -')
Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

Chef::Log.info("Creating WLST ")

template 'Template Undeploy Application' do
  source "fmw/wlst/undeployApplication.py.erb"
  path "/tmp/undeployApplication.py"
  mode '0700'
end

if asset_code == 'obpobu'
	appList = "com.ofss.fc.ui.restops,com.ofss.fc.ui.view.admin,com.ofss.fc.ui.view.admin.dashboard,com.ofss.fc.ui.view.developer"
elsif asset_code == 'obpobh'
	appList = "com.ofss.fc.module.rest.ops"
end

bash 'Undeploying Application' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /tmp/undeployApplication.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} #{appList}
    EOH
end