# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)


environment_name = node.chef_environment.downcase

_item_code = 'obpobh'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

pwd_vault = my_topology_vars['common']['password_vault_name']
orcl_home = '/oracle/app/product/db12/12.1.0'
rcu_prefix = my_topology_vars["#{_item_code}"]['database']['rcu_schema_prefix']
schema_name = "#{rcu_prefix}_OBP"
schema_pwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{_item_code}/#{rcu_prefix}").value)
svc_name = my_topology_vars["#{_item_code}"]['database']['service_name']

templatefile="sql/OBP_R262_KillScript_Westpac.sql.erb"

# The template list in source may contain more than 1 file but chef will always pick up the first one which would be the correct one from our sorting above
template "Sourcing the cleanup script from #{templatefile}" do
	source templatefile
	path "/tmp/OBP_R262_KillScript_Westpac.sql"
	mode '0600'
	user 'oracle'
	group 'oinstall'
end

oracle_sql "Performing Cleanup of #{schema_name}" do
	oracle_home orcl_home
	db_service_name svc_name
	db_host my_topology_vars["#{_item_code}"]['database']['scan_address']
	db_port my_topology_vars["#{_item_code}"]['database']['listen_port'].to_i
	db_username schema_name
	db_password schema_pwd
	as_sysdba false
	sql_file "/tmp/OBP_R262_KillScript_Westpac.sql"
	action :run
	user 'oracle'
	group 'oinstall'
end
