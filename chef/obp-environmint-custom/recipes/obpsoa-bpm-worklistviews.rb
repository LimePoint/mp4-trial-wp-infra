# Author: Harsha Gurram

# Recipe to update worklist/BPM related configurations

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

asset_code = "obpsoa"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
obpsoa_adminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpsoa_admin").value)
release_version = my_topology_vars["#{asset_code}"]['release_version']
bpm_worklistviews_dir = "/oracle/app/binaries/obpsoa/fmw/obpinstall/BPM_WorklistViews"


if release_version == '1.7.0'
	BPM_artifact = "BPM_WorklistViews.tar.gz.v4"
else
	BPM_artifact = "BPM_WorklistViews.tar.gz.v5"
end
puts "#{BPM_artifact}"

#Below DB Update No Longer required. Commenting out
=begin
Chef::Log.info('Executing SOA flexfields attr DB Update')

unless my_topology_vars['obpsoa']['database']['secondary_scan_address'].nil?
	oracle_sql "Executing DB Update of SOA flexfields attrs" do
		oracle_home '/oracle/stage/oracle_client/12.1.0/client_1'
		db_service_name my_topology_vars['obpsoa']['database']['service_name']
		db_host my_topology_vars['obpsoa']['database']['secondary_scan_address']
		db_port my_topology_vars['obpsoa']['database']['listen_port'].to_i
		db_username "OBPSOA_SOAINFRA"
		db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpsoa/OBPSOA").value)
		as_sysdba false
		sql "UPDATE WFATTRIBUTELABELMAP SET FORMATSTYLE = 'NUMBER' WHERE TASKATTRIBUTE LIKE 'ProtectedNumberAttribute%'"
		action :run
		user 'oracle'
		group 'oinstall'
		ignore_failure true
	end
end

oracle_sql "Executing DB Update of SOA flexfields attrs" do
	oracle_home '/oracle/stage/oracle_client/12.1.0/client_1'
	db_service_name my_topology_vars['obpsoa']['database']['service_name']
	db_host my_topology_vars['obpsoa']['database']['scan_address']
	db_port my_topology_vars['obpsoa']['database']['listen_port'].to_i
	db_username "OBPSOA_SOAINFRA"
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpsoa/OBPSOA").value)
	as_sysdba false
	sql "UPDATE WFATTRIBUTELABELMAP SET FORMATSTYLE = 'NUMBER' WHERE TASKATTRIBUTE LIKE 'ProtectedNumberAttribute%'"
	action :run
	user 'oracle'
	group 'oinstall'
end

=end

bash 'Copy artefacts to server' do
  code <<-EOH
    cd /oracle/app/binaries/obpsoa/fmw/obpinstall/;
    rm -rf BPM_WorklistViews
    cp -vf /oracle/stage/custom/csh/obpsoa/#{BPM_artifact} /oracle/app/binaries/obpsoa/fmw/obpinstall/;
    tar -xzf #{BPM_artifact};
    EOH
  Chef::Log.info('BPM_WorklistViews artifacts copied')
end
	
Chef::Log.info('Running migrateWorklist-views-import.sh ')

bash 'Execute migrateWorklist-views-import.sh' do
  code <<-EOH
  	cd #{bpm_worklistviews_dir};
  	sed -i 's/user = weblogic/user = obpsoa_admin/g' migration-views.properties;
  	sed -i 's/SOA_ADMIN_USER/obpsoa_admin/g' export_all_views.xml;
  	export MW_HOME=/oracle/app/binaries/obpsoa/fmw;
	. /oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/commEnv.sh;
	ant -f /oracle/app/binaries/obpsoa/fmw/soa/bin/ant-t2p-worklist.xml -Dbea.home=/oracle/app/binaries/obpsoa/fmw -Dsoa.home=/oracle/app/binaries/obpsoa/fmw/soa -Dmigration.properties.file=#{bpm_worklistviews_dir}/migration-views.properties -Dsoa.hostname=#{my_topology_vars["#{asset_code}"]['admin']['listen_address']} -Dsoa.rmi.port=17002 -Dsoa.admin.user=obpsoa_admin -Dsoa.admin.password=#{obpsoa_adminPassword} -Drealm=jazn.com -Dmigration.file=#{bpm_worklistviews_dir}/export_all_views.xml -Dmap.file=#{bpm_worklistviews_dir}/export_all_views_mapper.xml
    EOH
end

bash 'Execute Flexfields Update' do
  code <<-EOH
  	cd #{bpm_worklistviews_dir};
  	sed -i 's/user = weblogic/user = obpsoa_admin/g' migration-flexfields.properties;
  	export MW_HOME=/oracle/app/binaries/obpsoa/fmw;
	. /oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/commEnv.sh;
	ant -f /oracle/app/binaries/obpsoa/fmw/soa/bin/ant-t2p-worklist.xml -Dbea.home=/oracle/app/binaries/obpsoa/fmw -Dsoa.home=/oracle/app/binaries/obpsoa/fmw/soa -Dmigration.properties.file=#{bpm_worklistviews_dir}/migration-flexfields.properties -Dsoa.hostname=#{my_topology_vars["#{asset_code}"]['admin']['listen_address']} -Dsoa.rmi.port=17002 -Dsoa.admin.user=obpsoa_admin -Dsoa.admin.password=#{obpsoa_adminPassword} -Drealm=jazn.com -Dmigration.file=#{bpm_worklistviews_dir}/export_labels.xml -Dmap.file=#{bpm_worklistviews_dir}/export_taskDef_mapper.xml
    EOH
end