# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)


environment_name = node.chef_environment.downcase

_item_code = 'obpobh'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

asset_vars = my_topology_vars[_item_code.downcase]

pwd_vault = my_topology_vars['common']['password_vault_name']
orcl_home = '/oracle/app/product/db12/12.1.0'
rcu_prefix = my_topology_vars["#{_item_code}"]['database']['rcu_schema_prefix']
schema_name = "#{rcu_prefix}_OBP"
schema_pwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{_item_code}/#{rcu_prefix}").value)
sysdba_user = my_topology_vars["#{_item_code}"]['database']['sysdba_username']
syspwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{_item_code}/#{sysdba_user}").value)
svc_name = my_topology_vars["#{_item_code}"]['database']['service_name'].gsub('_', '')
orcl_sid = "#{svc_name}"[0..7]


# Find the correct file to run
version_string = my_topology_vars['obpobh']['release_version']
Chef::Log.info("version_string: #{version_string}")

template_list=Dir.glob("#{__dir__}/../templates/sql/#{_item_code.downcase}*.sql.erb").to_a
template_list.length.times { |t| template_list[t].gsub!("#{__dir__}/../templates/", "") }
# sort it
Chef::Log.info("unsorted template_list: #{template_list} from #{__dir__}/../../templates/sql/#{_item_code.downcase}*.sql.erb")
version_sort!(template_list, '.erb', '.sql', 2)

while Gem::Version.new(template_list[0].split('-')[2].to_s.gsub('.sql.erb', '')) > Gem::Version.new(version_string)
    template_list=template_list.drop(1)
end

Chef::Log.info("SQL File List: #{template_list}")
Chef::Log.info("SQL File List That Will Get Run: #{template_list[0]}")

directory "/oracle/app/oradata/#{orcl_sid}" do
    owner 'oracle'
    group 'oinstall'
    mode '0750'
    action :create
end

oracle_tablespace "Creating tablespace #{schema_name}" do
    user 'oracle'
    group 'oinstall'
    oracle_home orcl_home
    db_service_name orcl_sid
    db_username sysdba_user
    db_password syspwd
    as_sysdba true
    tablespace_name schema_name
    tablespace_type 'PERMANENT'
    datafile_name "#{schema_name}01.dbf"
end

oracle_user "Creating schema #{schema_name}" do
    user 'oracle'
    group 'oinstall'
    oracle_home orcl_home
    db_service_name svc_name
    db_username sysdba_user
    db_password syspwd
    as_sysdba true
    username schema_name
    password schema_pwd
    default_tablespace schema_name
    grant_clause 'connect,resource'
end

# The template list in source may contain more than 1 file but chef will always pick up the first one which would be the correct one from our sorting above
template "Privileges for #{schema_name}" do
    source template_list
    path "#{__dir__}/../files/#{rcu_prefix}-dbprivs.sql"
    variables(
        :username => schema_name
    )
    mode '0600'
    user 'oracle'
    group 'oinstall'
end

oracle_sql "Granting necessary privileges to #{schema_name}" do
    oracle_home orcl_home
    db_service_name svc_name
    db_host my_topology_vars["#{_item_code}"]['database']['scan_address']
    db_port my_topology_vars["#{_item_code}"]['database']['listen_port'].to_i
    db_username sysdba_user
    db_password syspwd
    as_sysdba true
    sql_file "#{__dir__}/../files/#{rcu_prefix}-dbprivs.sql"
    action :run
    user 'oracle'
    group 'oinstall'
end


# Create the OBP Read only schema
oracle_user "Creating schema OBPREADONLY" do
    user 'oracle'
    group 'oinstall'
    oracle_home orcl_home
    db_service_name svc_name
    db_username sysdba_user
    db_password syspwd
    as_sysdba true
    username 'obpreadonly'
    password Mint::AesEncryption.decrypt(PasswordVault.get_password(pwd_vault, 'obpobh', 'obpreadonly'))
    default_tablespace 'USERS'
    grant_clause 'connect'
end

oracle_sql "Grant Pivs to OBPREADONLY" do
    sql "Grant connect, select any table to obpreadonly"
    # FIXME: this is working around an MP bug
    db_service_name svc_name
    db_host my_topology_vars["#{_item_code}"]['database']['scan_address']
    db_port my_topology_vars["#{_item_code}"]['database']['listen_port'].to_i
    oracle_home orcl_home
    db_username sysdba_user
    db_password syspwd
    as_sysdba true
    user 'oracle'
    group 'oinstall'
end
