require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPOBH'

environment_name = node.chef_environment.downcase
db_env_name = "#{environment_name}".chomp('r').chomp('w').upcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']
dba_username = my_topology_vars['obpobh']['database']['sysdba_username'].upcase

#### Add asset specific code here ####

code = _item_code.downcase

# Process files and drop them to /tmp
template "Processing obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql" do
	source "sql/obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql.erb"
	path "/oracle/app/binaries/obpobh/fmw/obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql"
	variables(
		:dataBag => my_topology_vars,
		:envname => db_env_name
	)
	mode '0644'
end

unless my_topology_vars['obpobh']['database']['secondary_scan_address'].nil?
	oracle_sql "/oracle/app/binaries/obpobh/fmw/obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql" do
		oracle_home '/oracle/app/binaries/obpobh/dbclient'
		db_service_name my_topology_vars['obpobh']['database']['service_name']
		db_host my_topology_vars['obpobh']['database']['secondary_scan_address']
		db_port my_topology_vars['obpobh']['database']['listen_port'].to_i
		db_username 'OBPHOST_OBP'
		db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpobh/#{my_topology_vars['obpobh']['database']['rcu_schema_prefix']}").value)
		as_sysdba false
		sql_file "/oracle/app/binaries/obpobh/fmw/obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql"
		action :run
		user 'oracle'
		group 'oinstall'
		ignore_failure true
	end
	oracle_sql "Grant Execute On DBMS_CRYPTO" do
		oracle_home '/oracle/app/binaries/obpobh/dbclient'
		db_service_name my_topology_vars['obpobh']['database']['service_name']
		db_host my_topology_vars['obpobh']['database']['secondary_scan_address']
		db_port my_topology_vars['obpobh']['database']['listen_port'].to_i
		db_username 'INSTALL_DBA'
		db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpobh/INSTALL_DBA").value)
		as_sysdba true
		sql "GRANT EXECUTE ON SYS.DBMS_CRYPTO TO OBPHOST_OBP"
		action :run
		user 'oracle'
		group 'oinstall'
		ignore_failure true
	end
end
unless my_topology_vars['obpodi']['database']['secondary_scan_address'].nil?
	oracle_sql "Grant Execute On DBMS_LOCK" do
		oracle_home '/oracle/app/binaries/obpobh/dbclient'
		db_service_name my_topology_vars['obpodi']['database']['service_name']
		db_host my_topology_vars['obpodi']['database']['secondary_scan_address']
		db_port my_topology_vars['obpodi']['database']['listen_port'].to_i
		db_username 'INSTALL_DBA'
		db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpodi/INSTALL_DBA").value)
		as_sysdba true
		sql "GRANT EXECUTE ON SYS.DBMS_LOCK TO OBPODI_ODI_REPO, OBPODI_CSA_REPO"
		action :run
		user 'oracle'
		group 'oinstall'
		ignore_failure true
	end
end

oracle_sql "/oracle/app/binaries/obpobh/fmw/obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql" do
	oracle_home '/oracle/app/binaries/obpobh/dbclient'
	db_service_name my_topology_vars['obpobh']['database']['service_name']
	db_host my_topology_vars['obpobh']['database']['scan_address']
	db_port my_topology_vars['obpobh']['database']['listen_port'].to_i
	db_username 'OBPHOST_OBP'
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpobh/#{my_topology_vars['obpobh']['database']['rcu_schema_prefix']}").value)
	as_sysdba false
	sql_file "/oracle/app/binaries/obpobh/fmw/obp-environment-override-#{my_topology_vars['obpobh']['release_version']}.sql"
	action :run
	user 'oracle'
	group 'oinstall'
end

oracle_sql "Grant Execute On DBMS_CRYPTO" do
	oracle_home '/oracle/app/binaries/obpobh/dbclient'
	db_service_name my_topology_vars['obpobh']['database']['service_name']
	db_host my_topology_vars['obpobh']['database']['scan_address']
	db_port my_topology_vars['obpobh']['database']['listen_port'].to_i
	db_username dba_username
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpobh/#{dba_username}").value)
	as_sysdba true
	sql "GRANT EXECUTE ON SYS.DBMS_CRYPTO TO OBPHOST_OBP"
	action :run
	user 'oracle'
	group 'oinstall'
end

oracle_sql "Grant Execute On DBMS_LOCK" do
	oracle_home '/oracle/app/binaries/obpobh/dbclient'
	db_service_name my_topology_vars['obpodi']['database']['service_name']
	db_host my_topology_vars['obpodi']['database']['scan_address']
	db_port my_topology_vars['obpodi']['database']['listen_port'].to_i
	db_username dba_username
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpodi/#{dba_username}").value)
	as_sysdba true
	sql "GRANT EXECUTE ON SYS.DBMS_LOCK TO OBPODI_ODI_REPO, OBPODI_CSA_REPO"
	action :run
	user 'oracle'
	group 'oinstall'
end
