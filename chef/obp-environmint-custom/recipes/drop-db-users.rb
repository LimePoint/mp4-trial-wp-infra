require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

item_code = node.name.split('.')[0][-5..-3].downcase

asset_code = "obp#{item_code}"

schema_list = my_topology_vars["#{asset_code}"]['database']['custom_schema']

if asset_code == "obpobh"
    schema_list = my_topology_vars["#{asset_code}"]['database']['rcu_schema_prefix'] + "_OBP," + my_topology_vars["#{asset_code}"]['database']['custom_schema']
    base_dir = "/oracle/app/binaries/tmp"
else
    base_dir = "/oracle/app/binaries/#{asset_code}/tmp"
end


dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase

schema_array = schema_list.split(',')

schema_array.each do |schema_name|

    template "Processing drop-db-users.sql" do
        source "sql/drop-db-users.sql.erb"
        path "#{base_dir}/#{schema_name}-drop.sql"
        variables(
            :username => schema_name
        )
        mode '0644'
        user 'oracle'
        group 'oinstall'
    end    

    if schema_name.start_with?('OBPA')
        servicename = my_topology_vars["#{asset_code}"]['database']['obp_analytics_service_name']
    else
        schema_service_name = "#{schema_name}_service_name"
        if my_topology_vars["#{asset_code}"]['database']["#{schema_service_name.downcase}"]
            servicename = my_topology_vars["#{asset_code}"]['database']["#{schema_service_name.downcase}"]
        else
            servicename = my_topology_vars["#{asset_code}"]['database']['service_name']
        end
    end

    oracle_sql "#{base_dir}/#{schema_name}-drop.sql" do
        oracle_home "/oracle/app/binaries/#{asset_code}/dbclient"
        db_service_name servicename
        db_host my_topology_vars["#{asset_code}"]['database']['scan_address']
        db_username dba_username
        db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{dba_username}").value)
        db_port my_topology_vars["#{asset_code}"]['database']['listen_port'].to_i    
        as_sysdba true
        sql_file "#{base_dir}/#{schema_name}-drop.sql"
        action :run
        user 'oracle'
        group 'oinstall'
    end
end