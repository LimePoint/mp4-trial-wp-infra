# Author: Bharat Wadhwa

# Recipe to revoke the permission of odi creds step [to run the script - revokePermissions.py]

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']


asset_code = "obpodi"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
tmp_dir = '/oracle/app/binaries/obpodi/tmp'

Chef::Log.info('Connecting to domain -')
Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

Chef::Log.info("Creating WLST ")

template 'Template revokePermission.py Script' do
  source "fmw/wlst/revokePermissions.py.erb"
  path "#{tmp_dir}/revokePermissions.py"
  mode '0700'
end

bash 'Executing the revoke permissions for file:/oracle/app/binaries/obpodi/fmw/odi/sdk/lib/-' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{tmp_dir}/revokePermissions.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} "file:/oracle/app/binaries/obpodi/fmw/odi/sdk/lib/-" "oracle.security.jps.service.credstore.CredentialAccessPermission" "*" "Context=SYSTEM,mapName=*,keyName=*"
    EOH
end

bash 'Executing the revoke permissions for 	file:/oracle/app/binaries/obpodi/fmw/odi/jee/oracledi-agent/oracle.odi-agent.jar' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{tmp_dir}/revokePermissions.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} "file:/oracle/app/binaries/obpodi/fmw/odi/jee/oracledi-agent/oracle.odi-agent.jar" "oracle.security.jps.service.credstore.CredentialAccessPermission" "*" "Context=SYSTEM,mapName=*,keyName=*"
    EOH
end

bash 'Executing the revoke permissions for 	file:/oracle/app/binaries/obpodi/fmw/oracle_common/modules/org.springframework_3.1.0.jar' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{tmp_dir}/revokePermissions.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} "file:/oracle/app/binaries/obpodi/fmw/oracle_common/modules/org.springframework_3.1.0.jar" "oracle.security.jps.service.credstore.CredentialAccessPermission" "*" "Context=SYSTEM,mapName=*,keyName=*"
    EOH
end
