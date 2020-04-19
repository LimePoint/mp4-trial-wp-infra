# Author: Chinmoy Rath

# This recipe updates OIM Frontend URL
# This can be run over and over again.

node.run_state.merge!(node)

environment_name = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

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

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"
oimFrontEndUrl = "https://#{my_topology_vars["#{asset_code}"]['frontend']['otd_vip_name']}"

Chef::Log.info('Connecting to domain -')
Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

Chef::Log.info("Creating WLST ")

template 'Template Update oimFrontEndUrl' do
  source "fmw/wlst/setOIMFrontEndUrl.py.erb"
  path "/tmp/setOIMFrontEndUrl.py"
  mode '0700'
end

bash 'Updating OIM Frontend Url' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /tmp/setOIMFrontEndUrl.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} #{oimFrontEndUrl}
    EOH
end