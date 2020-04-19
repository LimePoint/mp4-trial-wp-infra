# Recipe: Recipe to repoint Domain to New DB Instance. 
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
  end
  if asset_code == 'obpcid'
    asset_code = 'obpcim'
  end
end 	

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
admin_domain_home = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}"
managed_domain_home = "/oracle/app/binaries/runtime/#{asset_code}/domains/#{domain_name}"
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
dcms_database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['dcms_service_name']}"

release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_log_dir = "/oracle/app/binaries/12c_upgrade"
dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase
service_name = my_topology_vars["#{asset_code}"]['database']['service_name']


if release_version != '1.7.0'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

if my_topology_vars["#{asset_code}"]['migrate_env'] == 'false' or my_topology_vars["#{asset_code}"]['migrate_env'].nil?
  Chef::Log.info ('No VM Migration Required, Only DB Migration')
else
  Chef::Log.info ('VM Migration Required, proceeding with updating VM Configuration')
  #Code to Update Coonfigurations to point to new VM Hostnames
end

bash 'Update Domain to Point to new DB Service' do
  code <<-EOH
  echo "Check if any java process running"
	java_num=`ps -ef|grep java|grep #{asset_code} | wc -l`
	if [ $java_num -gt 1 ];then
  	echo "Appears some java process running, Verify and shut it down to proceed"
  	exit 1
	else
  	echo "Appears No java process running, proceeding with Upgrade readiness"
    echo "Updating DB Instance References to point to new DB in domain home - #{admin_domain_home}"
    cd #{admin_domain_home}/config/jdbc
    sed -i '/<url>/c\<url>jdbc:oracle:thin:@#{database_url}<\/url>' *.xml
    set -- DCMS*.xml ; [ -f "$1" ] && sed -i '/<url>/c\<url>jdbc:oracle:thin:@#{dcms_database_url}<\/url>' DCMS*.xml
    if [[ "#{asset_code}" = obp*im ]]; then
      echo "updating jpsconfig.xml, config.xml, bipublisher datasource details"
      grep -lIR CBC.._IDM_PRIM | xargs sed -i 's|CBC.._IDM_PRIM|#{service_name}|g' #{admin_domain_home}/config/config.xml
      grep -lIR CBC.._IDM_PRIM | xargs sed -i 's|CBC.._IDM_PRIM|#{service_name}|g' #{admin_domain_home}/config/bipublisher/repository/Admin/DataSource/datasources.xml
      cd #{admin_domain_home}/config/fmwconfig
      grep -lIR CBC.._IDM_PRIM | xargs sed -i 's|CBC.._IDM_PRIM|#{service_name}|g'
    fi  
    if [ -d "/oracle/app/binaries/runtime" ]; then
			cd #{managed_domain_home}/config/jdbc
      echo "Updating DB Instance References to point to new DB in domain home - #{managed_domain_home}"
      sed -i '/<url>/c\<url>jdbc:oracle:thin:@#{database_url}<\/url>' *.xml
      set -- DCMS*.xml ; [ -f "$1" ] && sed -i '/<url>/c\<url>jdbc:oracle:thin:@#{dcms_database_url}<\/url>' DCMS*.xml
      sed -i '/JdbcConnectionString/c\JdbcConnectionString=jdbc:oracle:thin:@#{database_url}' #{managed_domain_home}/ucm/cs/config/config.cfg
      sed -i '/JdbcConnectionString/c\JdbcConnectionString=jdbc:oracle:thin:@#{database_url}' /oracle/app/runtime/#{asset_code}/#{environment_name}/ucm/cs/config/config.cfg
  	fi
  	mkdir -v #{upgrade_log_dir}
  	echo "Completed repointing Domain to new DB Instance"
	fi
  EOH
end
