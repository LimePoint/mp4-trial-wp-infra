require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPDOC'

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#### Add asset specific code here ####

code = _item_code.downcase

# Process files
template 'Processing documaker-obp-admin.sql' do
	source "sql/documaker-obp-admin.sql.erb"
	path '/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-obp-admin.sql'
	variables(
		variables(
			:dataBag => my_topology_vars,
			:environment_name => environment_name
		)
	)
	mode '0644'
end

template 'Processing documaker-obp-asline.sql' do
	source "sql/documaker-obp-asline.sql.erb"
	path '/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-obp-asline.sql'
	mode '0644'
end

oracle_sql "/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-obp-admin.sql" do
	oracle_home '/oracle/app/binaries/obpdoc/dbclient'
	db_service_name my_topology_vars['obpdoc']['database']['service_name']
	db_host my_topology_vars['obpdoc']['database']['scan_address']
	db_port my_topology_vars['obpdoc']['database']['listen_port'].to_i
	db_username 'DMKR_ADMIN'
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpdoc/#{my_topology_vars['obpdoc']['database']['rcu_schema_prefix']}").value)
	as_sysdba false
	sql_file '/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-obp-admin.sql'
	action :run
	user 'oracle'
	group 'oinstall'
	not_if { ::File.exist?('/oracle/app/binaries/obpdoc/fmw/odee_12/.documaker-obp-admin.sql') }
end

bash 'OBP Admin Check' do
	code "touch /oracle/app/binaries/obpdoc/fmw/odee_12/.documaker-obp-admin.sql"
end

oracle_sql "/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-obp-asline.sql" do
	oracle_home '/oracle/app/binaries/obpdoc/dbclient'
	db_service_name my_topology_vars['obpdoc']['database']['service_name']
	db_host my_topology_vars['obpdoc']['database']['scan_address']
	db_port my_topology_vars['obpdoc']['database']['listen_port'].to_i
	db_username 'DMKR_ASLINE'
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpdoc/#{my_topology_vars['obpdoc']['database']['rcu_schema_prefix']}").value)
	as_sysdba false
	sql_file '/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-obp-asline.sql'
	action :run
	user 'oracle'
	group 'oinstall'
	not_if { ::File.exist?('/oracle/app/binaries/obpdoc/fmw/odee_12/.documaker-obp-asline.sql') }
end

bash 'OBP Asline Check' do
	code "touch /oracle/app/binaries/obpdoc/fmw/odee_12/.documaker-obp-asline.sql"
end
