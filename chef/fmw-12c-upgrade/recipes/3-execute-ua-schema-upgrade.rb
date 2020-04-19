#Recipe: Recipe to upgrade 11g RCU Schemas to 12c. 
# Author: Harsha Gurram

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
if item_code == 'ucm'
  item_code = 'ipm'
end
asset_code = "obp#{item_code}"

if my_topology_vars["#{asset_code}"]['dns_domain_name'] != '.wpdev.mintpress.io' && !['svp3r','prd3r','psp3'].include?(environment_name) && ['obpoid','obpcid'].include?(asset_code)
  if asset_code == 'obpoid'
    asset_code = 'obpoim'
    item_code = 'oim'
  end
  if asset_code == 'obpcid'
    asset_code = 'obpcim'
    item_code = 'cim'
  end
end

asset_vars = my_topology_vars["#{asset_code}"]


domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
admin_domain_home = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}"
managed_domain_home = "/oracle/app/binaries/runtime/#{asset_code}/domains/#{domain_name}"
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_log_dir = "/oracle/app/binaries/12c_upgrade"
fmw_12c_home = "/oracle/app/binaries/#{item_code}12c/fmw"
dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase
if ['obpoim','obpcim'].include?(asset_code)
  schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}-MDS").value)
else
  schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}").value)
end  
dba_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{dba_username.upcase}").value)


if release_version != '1.7.0'
  Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
  return
end

template "Processing #{asset_code}_schema_upgrade.rsp" do
  source "#{asset_code}_schema_upgrade.rsp.erb"
  path "#{upgrade_log_dir}/#{asset_code}_schema_upgrade.rsp"
  variables(
    :domain_home => managed_domain_home,
    :db_url => database_url,
    :rcu_prefix => asset_code,
    :schema_password => schema_password,
    :dba_user => dba_username,
    :sysdba_password => dba_password
  )
  mode '0644'
  user 'oracle'
  group 'oinstall'
end


bash 'Execute Schema Upgrade and Create New RCU Schemas' do
  code <<-EOH
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    SET='\033[0m'
    echo "Running Schema Upgrade Utility"
    cd #{fmw_12c_home}/oracle_common/upgrade/bin;
    ./ua -schemaUpgrade -logDir #{upgrade_log_dir} -response #{upgrade_log_dir}/#{asset_code}_schema_upgrade.rsp;
    if [ $? -ne 0 ]; then
      echo -e "##########################################################################################################################################################\n" 
      echo -e "${RED}Schema Upgrade Failed, Check the Logs located at #{upgrade_log_dir} ${SET}"
      echo -e "\n##########################################################################################################################################################\n"
        exit 1
    else
      echo -e "##########################################################################################################################################################\n"
      echo -e "${GREEN} Schema Upgrade completed successfully for the domain located at - #{admin_domain_home}. Review the logs located at #{upgrade_log_dir} and ensure that the Required schemas are upgraded and created as required before proceeding to next step.${SET}"
      echo -e "\n##########################################################################################################################################################\n"
    fi
    EOH
    only_if { ::File.exist?("#{upgrade_log_dir}/#{asset_code}_schema_upgrade.rsp") }
end

if asset_code == 'obpipm'

  template "Processing #{asset_code}_mds_schema_upgrade.rsp" do
    source "#{asset_code}_mds_schema_upgrade.rsp.erb"
    path "#{upgrade_log_dir}/#{asset_code}_mds_schema_upgrade.rsp"
    variables(
      :domain_home => managed_domain_home,
      :db_url => database_url,
      :rcu_prefix => asset_code,
      :schema_password => schema_password,
      :dba_user => dba_username,
      :sysdba_password => dba_password
    )
    mode '0644'
    user 'oracle'
    group 'oinstall'
  end


  bash 'Execute MDS Schema Upgrade' do
    code <<-EOH
      RED='\033[0;31m'
      GREEN='\033[0;32m'
      SET='\033[0m'
      echo "Running Schema Upgrade Utility"
      cd #{fmw_12c_home}/oracle_common/upgrade/bin;
      ./ua -schemaUpgrade -logDir #{upgrade_log_dir} -response #{upgrade_log_dir}/#{asset_code}_mds_schema_upgrade.rsp;
      if [ $? -ne 0 ]; then
        echo -e "##########################################################################################################################################################\n" 
        echo -e "${RED}Schema Upgrade Failed, Check the Logs located at #{upgrade_log_dir} ${SET}"
        echo -e "\n##########################################################################################################################################################\n"
          exit 1
      else
        echo -e "##########################################################################################################################################################\n"
        echo -e "${GREEN} Schema Upgrade completed successfully for the domain located at - #{admin_domain_home}. Review the logs located at #{upgrade_log_dir} and ensure that the Required schemas are upgraded and created as required before proceeding to next step.${SET}"
        echo -e "\n##########################################################################################################################################################\n"
      fi
      EOH
      only_if { ::File.exist?("#{upgrade_log_dir}/#{asset_code}_mds_schema_upgrade.rsp") }
  end

end

# OIM specific tasks
if ['obpoim','obpcim'].include?(asset_code)
  bash 'Create Additional for STB and IAU Schemas required for OIM 12c' do
    code <<-EOH
      cd #{fmw_12c_home}/oracle_common/bin;
      (echo #{dba_password}; echo #{schema_password}) | ./rcu -silent -createRepository \
      -connectString #{database_url} \
      -dbUser #{dba_username} -dbRole sysdba  \
      -schemaPrefix #{asset_code} \
      -component IAU -component IAU_APPEND \
      -component IAU_VIEWER -component STB \
      -useSamePasswordForAllSchemaUsers true \
      -selectDependentsForComponents true
      EOH
    ignore_failure true
  end
end

# Check DB Schema Versions post upgrade
template "Processing validateSchemas.sql" do
  source "validateSchemas.sql.erb"
  path "#{upgrade_log_dir}/validateSchemas.sql"
  variables(
      :rcu_prefix => asset_code
  )
  mode '0644'
  user my_topology_vars['common']['target_user_name']
  group my_topology_vars['common']['target_group_name']
end    

oracle_sql "#{upgrade_log_dir}/validateSchemas.sql" do
  oracle_home "#{fmw_12c_home}/../dbclient"
  db_service_name asset_vars['database']['service_name']
  db_host asset_vars['database']['scan_address']
  db_port asset_vars['database']['listen_port'].to_i    
  db_username dba_username
  db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{dba_username.upcase}").value)
  as_sysdba true
  sql_file "#{upgrade_log_dir}/validateSchemas.sql"
  action :run
  user 'oracle'
  group 'oinstall'
end