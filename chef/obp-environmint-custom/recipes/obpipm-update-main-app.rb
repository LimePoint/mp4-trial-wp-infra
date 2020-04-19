
# Recipe:: obpipm-config-main-app
# Recipe to update IPM App definitions
# Author: Harsha Gurram



environment_name = node.chef_environment.downcase
node_sn = node.name.split('.')[0].downcase
asset_code='obpipm'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
asset_vars = my_topology_vars[asset_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']
tmp_dir = '/oracle/app/binaries/obpipm/tmp'
as_domain_home = '/oracle/app/runtime/obpipm/domains/obpipm_domain'
ms_domain_home = '/oracle/app/binaries/runtime/obpipm/domains/obpipm_domain'
intradoc_dir = "/oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/"
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
obpipm_adminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpipm_admin").value)
custom_source = "/oracle/stage/custom/csh"
fmw_install_path = "/oracle/app/binaries/obpipm/fmw"
java_install_path = "/oracle/app/binaries/obpipm/java"

#Storage Rule Creation
bash 'Create IPM FS Rule' do
  code <<-EOH
    echo "#{custom_source}/#{asset_code}/ipmFSStorageRule.sh #{java_install_path} #{custom_source}/#{asset_code} http://#{asset_vars['ucm_server']['listen_address']}#{asset_vars['dns_domain_name']}:#{asset_vars['ucm_server']['listen_port']} weblogic #{weblogicAdminPassword} #{fmw_install_path} #{environment_name}"
    #{custom_source}/#{asset_code}/ipmFSStorageRule.sh #{java_install_path} #{custom_source}/#{asset_code} http://#{asset_vars['ucm_server']['listen_address']}#{asset_vars['dns_domain_name']}:#{asset_vars['ucm_server']['listen_port']} weblogic #{weblogicAdminPassword} #{fmw_install_path} #{environment_name}
    EOH
end

#WLST Script
template 'ipm_app_import.py.erb' do
  source "fmw/obpipm/ipm_app_import.py.erb"
  path "#{tmp_dir}/ipm_app_import.py"
  variables(
      :app_definition_xml => "#{as_domain_home}/ipm_main_app_definition.xml"
  )
  mode '0700'
  end

#IPM APP Definitions File
template 'ipm_main_app_definition.xml.erb' do
  source "fmw/obpipm/ipm_main_app_definition.xml.erb"
  path "#{as_domain_home}/ipm_main_app_definition.xml"
  mode '0700'
  end

# Update APP
bash "Configuring IPM MAIN app" do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/wcc_11.1/common/bin/wlst.sh #{tmp_dir}/ipm_app_import.py obpipm_admin #{obpipm_adminPassword} #{asset_vars['ipm_server']['listen_address']} MAIN Imported
    EOH
  only_if "cat /oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/data/ipmsys/apps/*.hda | grep 'ApplicationName=MAIN'"
end