require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']


# OBPOIM and OBPCIM run on the same db, hence running the XA views only once.

asset_to_run = "obpoim"
oracle_sql "initxa.sql - #{asset_to_run}" do
	oracle_home "/oracle/stage/sqlplus/client/11.2.0"
	db_service_name my_topology_vars["#{asset_to_run}"]['database']['service_name']
	db_host my_topology_vars["#{asset_to_run}"]['database']['scan_address']
	db_port my_topology_vars["#{asset_to_run}"]['database']['listen_port'].to_i
	db_username my_topology_vars["#{asset_to_run}"]['database']['sysdba_username'].upcase
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_to_run}/#{my_topology_vars[asset_to_run]['database']['sysdba_username'].upcase}").value)
	as_sysdba true
	sql_file "/oracle/stage/sqlplus/12.1.0.2/xa_views/initxa.sql"
	action :run
	user 'oracle'
	group 'oinstall'
end

oracle_sql "xaview.sql - #{asset_to_run}" do
	oracle_home "/oracle/stage/sqlplus/client/11.2.0"
	db_service_name my_topology_vars["#{asset_to_run}"]['database']['service_name']
	db_host my_topology_vars["#{asset_to_run}"]['database']['scan_address']
	db_port my_topology_vars["#{asset_to_run}"]['database']['listen_port'].to_i
	db_username my_topology_vars["#{asset_to_run}"]['database']['sysdba_username'].upcase
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_to_run}/#{my_topology_vars[asset_to_run]['database']['sysdba_username'].upcase}").value)
	as_sysdba true
	sql_file "/oracle/stage/sqlplus/12.1.0.2/xa_views/xaview.sql"
	action :run
	user 'oracle'
	group 'oinstall'
end

oracle_sql "Recompile Schema - SYS" do
	oracle_home "/oracle/stage/sqlplus/client/11.2.0"
	db_service_name my_topology_vars["#{asset_to_run}"]['database']['service_name']
	db_host my_topology_vars["#{asset_to_run}"]['database']['scan_address']
	db_port my_topology_vars["#{asset_to_run}"]['database']['listen_port'].to_i
	db_username my_topology_vars["#{asset_to_run}"]['database']['sysdba_username'].upcase
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_to_run}/#{my_topology_vars[asset_to_run]['database']['sysdba_username'].upcase}").value)
	as_sysdba true
	sql "EXEC UTL_RECOMP.recomp_parallel(4, '#{my_topology_vars[asset_to_run]['database']['sysdba_username'].upcase}')"
	action :run
	user 'oracle'
	group 'oinstall'
end