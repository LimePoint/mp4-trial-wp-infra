# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

_item_code = 'obpobh'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

asset_vars = my_topology_vars[_item_code.downcase]

pwd_vault 		= my_topology_vars['common']['password_vault_name']
orcl_home 		= '/oracle/app/product/db12/12.1.0'
rcu_prefix 		= my_topology_vars["#{_item_code}"]['database']['rcu_schema_prefix']
schema_name 	= "#{rcu_prefix}_OBP"
sysdba_user 	= my_topology_vars["#{_item_code}"]['database']['sysdba_username']
syspwd 			= Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{_item_code}/#{sysdba_user}").value)
svc_name 		= my_topology_vars["#{_item_code}"]['database']['service_name'].gsub('_','')

# This block will execute the 'sql_file' ONLY IF there are no connected sessions to the OBPHOST schema
#
template "Preparing to drop #{schema_name}" do
	source "sql/drop-dbschema.sql.erb"
	path "#{__dir__}/../files/drop-#{schema_name}.sql"
	variables(
		:username => schema_name
	)
	mode '0600'
	user 'oracle'
	group 'oinstall'
end

oracle_sql "Droping schema #{schema_name}" do
	oracle_home orcl_home
	db_service_name svc_name
	db_host my_topology_vars["#{_item_code}"]['database']['scan_address']
	db_port my_topology_vars["#{_item_code}"]['database']['listen_port'].to_i
	db_username sysdba_user
	db_password syspwd
	as_sysdba true
	sql_file "#{__dir__}/../files/drop-#{schema_name}.sql"
	action :run
	user 'oracle'
	group 'oinstall'
end
