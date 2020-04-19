# Author: Harsha Gurram

# Recipe to reset coherence keystore for stronger security and post patching (July 2018 PSU) step [to run the script - softlockEnableDisable.py]

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']


asset_code = "obpoam"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
keystorePassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/keystorepass").value)
keystore_loc = '/oracle/app/runtime/obpoam/domains/obpoam_domain/config/fmwconfig'
tmp_dir = '/oracle/app/binaries/obpoam/tmp'

Chef::Log.info('Connecting to domain -')
Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

Chef::Log.info("Creating WLST ")

template 'Template softlockEnableDisable Script' do
  source "fmw/wlst/softlockEnableDisable.py.erb"
  path "#{tmp_dir}/softlockEnableDisable.py"
  mode '0700'
end

bash 'Executing Post Patching wlst' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/iam_11.1/common/bin/wlst.sh #{tmp_dir}/softlockEnableDisable.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
end