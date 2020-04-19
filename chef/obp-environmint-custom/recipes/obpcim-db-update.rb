require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

asset_code = "obpcim"

schema_name = "OBPCIM_OIM"

base_dir = "/oracle/app/binaries/#{asset_code}/tmp"

template "Processing obpcim-manage-pwd.sql" do
	source "sql/obpcim-manage-pwd.sql.erb"
	path "#{base_dir}/obpcim-manage-pwd.sql"
	variables(
		:username => schema_name,
		:password => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/OBPCIM-MDS").value)
	)
	mode '0644'
	user 'oracle'
	group 'oinstall'
end

oracle_sql "#{base_dir}/obpcim-manage-pwd.sql" do
	oracle_home "/oracle/app/binaries/#{asset_code}/dbclient"
	db_service_name my_topology_vars["#{asset_code}"]['database']['service_name']
	db_host my_topology_vars["#{asset_code}"]['database']['scan_address']
	db_port my_topology_vars["#{asset_code}"]['database']['listen_port'].to_i
	db_username schema_name
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/OBPCIM-MDS").value)
	as_sysdba false
	sql_file "#{base_dir}/obpcim-manage-pwd.sql"
	action :run
	user 'oracle'
	group 'oinstall'
end
