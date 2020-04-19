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

if environment_name =~ /^prd/ or environment_name =~ /^svp/
	# Load the other data bag if in prod or svp
	# do not do this for W sites as that will override the sequence of jms
	# so if this WSDC site, do not do anything
	# TODO: There has to be a way to do this specifically for WSDC in case RCC is down
	if environment_name[-1,1] == "w"
		# the Environment is WSDC
		Chef::Log.info ('Environment is SVP or PRD and in WSDC, doing nothing')
		return
	else
		other_env = "#{environment_name}".chomp('r') << 'w'
		dataBagWSDC = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{other_env}_vars.json"))
	end
end

# Find the list of documaker hosts
jmshosts = my_topology_vars['obpdoc']['hostnameList'].sort

val = "t3://"
# This is the documaker start port, in the future ports will also go to databags so this code will be better
start_port = my_topology_vars['obpdoc']['jms_server']['listen_port'].to_i
jmshosts.each do |k|
  val = val +  k + '-prv:' + start_port.to_s + ","
   start_port = start_port + 1
end

if !dataBagWSDC.nil? 
  # Add the WSDC hosts in the list but reset the port numbers
	jmshosts = dataBagWSDC['obpdoc']['hostnameList'].sort
	start_port = dataBagWSDC['obpdoc']['jms_server']['listen_port'].to_i
	jmshosts.each do |k|
		val = val +  k + '-prv:' +  start_port.to_s + ","
		start_port = start_port + 1
	end
end

# Remove the last , from val
val = val.chomp(',') 

# Switch for 2.6.1
if my_topology_vars['obpdoc']['release_version'].nil?
	sql_path = '/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-configs.sql'
else
	sql_path = "/oracle/app/binaries/obpdoc/fmw/odee_12/documaker-configs-#{my_topology_vars['obpdoc']['release_version']}.sql"
end

# Process files and drop them to the server
template 'Processing documaker-configs.sql' do
	source "sql/documaker-configs-#{my_topology_vars['obpdoc']['release_version']}.sql.erb"
	path sql_path
	variables(
		:jmshosts => val,
		:documakerSOAVIP => "https://#{my_topology_vars['obpdoc']['frontend']['otd_vip_name']}:#{my_topology_vars['obpdoc']['frontend']['soa_port']}",
		:documakerDMKRVIP => "https://#{my_topology_vars['obpdoc']['frontend']['otd_vip_name']}:#{my_topology_vars['obpdoc']['frontend']['dmkr_port']}",
		:JMSDMKRT3VIP => "t3://#{my_topology_vars['obpdoc']['frontend']['otd_vip_name']}:#{my_topology_vars['obpdoc']['frontend']['t3_jms_vip_port']}",
		:obpHostVIP => "https://#{my_topology_vars['obpobh']['frontend']['otd_vip_name']}:#{my_topology_vars['obpobh']['frontend']['obh_port']}",
		:ipmVIP => "https://#{my_topology_vars['obpipm']['frontend']['otd_vip_name']}:#{my_topology_vars['obpipm']['frontend']['ipm_port']}"
	)
	mode '0644'
end

unless my_topology_vars['obpdoc']['database']['secondary_scan_address'].nil?
	oracle_sql "#{sql_path}" do
		oracle_home '/oracle/app/binaries/obpdoc/dbclient'
		db_service_name my_topology_vars['obpdoc']['database']['service_name']
		db_host my_topology_vars['obpdoc']['database']['secondary_scan_address']
		db_port my_topology_vars['obpdoc']['database']['listen_port'].to_i
		db_username 'DMKR_ADMIN'
		db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpdoc/#{my_topology_vars['obpdoc']['database']['rcu_schema_prefix']}").value)
		as_sysdba false
		sql_file "#{sql_path}"
		user 'oracle'
		group 'oinstall'
		action :run
		ignore_failure true
	end
end
oracle_sql "#{sql_path}" do
	oracle_home '/oracle/app/binaries/obpdoc/dbclient'
	db_service_name my_topology_vars['obpdoc']['database']['service_name']
	db_host my_topology_vars['obpdoc']['database']['scan_address']
	db_port my_topology_vars['obpdoc']['database']['listen_port'].to_i
	db_username 'DMKR_ADMIN'
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpdoc/#{my_topology_vars['obpdoc']['database']['rcu_schema_prefix']}").value)
	as_sysdba false
	sql_file "#{sql_path}"
	user 'oracle'
	group 'oinstall'
	action :run
end

