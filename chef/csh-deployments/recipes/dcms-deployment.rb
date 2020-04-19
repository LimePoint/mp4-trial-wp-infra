
# Recipe:: dcms-deploy
# DCMS Deployment recipe
# Author: Harsha Gurram
#


environment_name = node.chef_environment.downcase
node_sn = node.name.split('.')[0].downcase
asset_code='obpipm'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))
my_topology_vars = my_dep_vars.merge(my_topology_vars)
asset_vars = my_topology_vars[asset_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']
deployment_dir = '/oracle/app/binaries/deployments/dcms'
build_version = my_topology_vars['dcms']['build_version']
artifactory_url = my_topology_vars['dcms']['artifactory_url']
as_domain_home = '/oracle/app/runtime/obpipm/domains/obpipm_domain'
ms_domain_home = '/oracle/app/binaries/runtime/obpipm/domains/obpipm_domain'
intradoc_dir = "/oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/"
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
obpipm_adminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpipm_admin").value)


directory "#{deployment_dir}" do
  owner "oracle"
  group "oinstall"
  mode 0755
  recursive true
  action :create
  not_if { ::Dir.exists?("#{deployment_dir}") } 
end

# 1. DOWNLOAD AND COPY JARS 


bash "Cleaning up old artefacts" do
  code <<-EOH
    cd #{deployment_dir}
    rm -rf WestpacOWCLibs WestpacOwcProperties WestpacOwcImport WestpacOwcSQLs
    mkdir -p WestpacOWCLibs WestpacOwcProperties WestpacOwcImport WestpacOwcSQLs
    EOH
end

  log "DOWNLOADING BUILD VERSION - #{build_version}"


remote_file "#{deployment_dir}/WestpacOWCLibs/WestpacOWCLibs-#{build_version}.zip" do
  source "#{artifactory_url}/WestpacOWCLibs/#{build_version}/WestpacOWCLibs-#{build_version}.zip"
  owner 'oracle'
  group 'oinstall'
  mode '0755'
  action :create
end

log "Extracting ZIP for Jars"

bash "Extracting required jars" do
  code <<-EOH
    cd #{deployment_dir}/WestpacOWCLibs
    unzip WestpacOWCLibs-#{build_version}.zip
    chmod -R 755 *
    EOH
  only_if { ::File.exist?("#{deployment_dir}/WestpacOWCLibs/WestpacOWCLibs-#{build_version}.zip") }
end

log "Copying Jars"


bash "copy jars to #{ms_domain_home}/lib" do
  code <<-EOH
    cd #{deployment_dir}/WestpacOWCLibs/WestpacOWCLibs
    rsync -avz *.jar #{ms_domain_home}/lib/
    EOH
end

# Run Deployment Only From Primary Node

if node_sn == my_topology_vars['dcms']['dep_primary_node']
# 2. DCMS APP CONFIGURATION

  template 'dcms_app_import.py.erb' do
    source "dcms/dcms_app_import.py.erb"
    path "#{deployment_dir}/dcms_app_import.py"
    variables(
        :app_definition_xml => "#{deployment_dir}/dcms_app_definition.xml",
        :action => "Add"
    )
    mode '0700'
    end

  template 'dcms_app_definition.xml.erb' do
    source "dcms/dcms_app_definition.xml.erb"
    path "#{deployment_dir}/dcms_app_definition.xml"
    mode '0700'
    end

  log "Creating DCMS APP"

  bash "Creating DCMS app" do
    code <<-EOH
      /oracle/app/binaries/#{asset_code}/fmw/wcc_11.1/common/bin/wlst.sh #{deployment_dir}/dcms_app_import.py obpipm_admin #{obpipm_adminPassword} #{asset_vars['ipm_server']['listen_address']}
      EOH
    not_if "cat /oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/data/ipmsys/apps/*.hda | grep 'ApplicationName=DCMSDocuments'"
  end

  bash "Checking if DCMS app is created" do
    code <<-EOH
      cat /oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/data/ipmsys/apps/*.hda | grep "ApplicationName=DCMSDocuments"
      if [ $? -ne 0 ]; then 
      echo "DCMSDocuments APP Doesn't exist, erroring out"
      exit 1
      fi
      EOH
  end

  if my_topology_vars['dcms']['ipm_app_id'].nil?
    log "DCMS APP ID MISSING IN DEP_VARS EXITING"
    return
  end


# 3. DCMS META DATA PROPERTIES

  if environment_name.end_with? "r"
    data_center = "WSDC"
  elsif node_sn[3] == "r"
    data_center = "RDC"
  elsif node_sn[3] == "w"
    data_center = "WSDC"
  else
    puts 'Cant determine datacenter id'
    return
  end
  log "----------- DATA CENTER ID is #{data_center} ---------"


  bash 'Backup config.cfg' do
    code <<-EOH
      cp #{intradoc_dir}/config/config.cfg #{intradoc_dir}/config/config.cfg.bkp.$(date +"%Y%m%d_%H%M%S")
      EOH
  end
  log 'config.cfg backed up.'

  template "Processing dcms_metadata.properties" do
    source "dcms/dcms_metadata.properties.erb"
    path "#{deployment_dir}/dcms_metadata.properties"
    variables(
      :IPMAppId => my_topology_vars['dcms']['ipm_app_id'],
      :DC => data_center
    )
    mode '0644'
    user 'oracle'
    group 'oinstall'
  end

  config_file  = "#{intradoc_dir}/config/config.cfg"

  ruby_block "Modify config.cfg file #{config_file}" do
    block do
      tempfile = "#{deployment_dir}/dcms_metadata.properties"
      fline = File.open(tempfile, "r")
      fline.each_line{ |param|
        file = Chef::Util::FileEdit.new(config_file)
        file.insert_line_if_no_match(/#{param}/, "#{param}")
        file.search_file_delete_line(/DocumentReconProcessEventHours=3,9,23/)
        file.write_file
      }
    end
    only_if { ::File.exists?(config_file) }
  end

# 4. DOWNLOAD PROPERTIES AND SYNC
  bash "copy jars to #{as_domain_home}/lib" do
    code <<-EOH
      cd #{deployment_dir}/WestpacOWCLibs/WestpacOWCLibs
      rsync -avz *.jar #{as_domain_home}/lib/
    EOH
  end

  log "Downloading Properties"

  remote_file "#{deployment_dir}/WestpacOwcProperties/WestpacOwcProperties-#{build_version}.zip" do
    source "#{artifactory_url}/WestpacOwcProperties/#{build_version}/WestpacOwcProperties-#{build_version}.zip"
    owner 'oracle'
    group 'oinstall'
    mode '0755'
    action :create
  end

  log "Extracting ZIP for Properties"

  bash "Extracting Properties" do
    code <<-EOH
      cd #{deployment_dir}/WestpacOwcProperties
      unzip WestpacOwcProperties-#{build_version}.zip
      chmod -R 755 *
      EOH
    only_if { ::File.exist?("#{deployment_dir}/WestpacOwcProperties/WestpacOwcProperties-#{build_version}.zip") }
  end

  log "Syncing log4j Properties"

  bash "copy log4j properties" do
    code <<-EOH
      cd #{deployment_dir}/WestpacOwcProperties/Properties
      rsync -avz log4j.properties /oracle/app/dcms/owcimport/
      EOH
  end

# 5. DOWNLOAD DEPLOYMENT COMPONENT

  log "Downloading Deployment Component"

  remote_file "#{deployment_dir}/WestpacOwcImport/WestpacOwcImport-#{build_version}.zip" do
    source "#{artifactory_url}/WestpacOwcImport/#{build_version}/WestpacOwcImport-#{build_version}.zip"
    owner 'oracle'
    group 'oinstall'
    mode '0755'
    action :create
  end

  log "Extracting ZIP for Deployment zip"

  bash "Extracting Deployment Component zip" do
    code <<-EOH
      cd #{deployment_dir}/WestpacOwcImport
      unzip WestpacOwcImport-#{build_version}.zip
      chmod -R 755 *
      EOH
    only_if { ::File.exist?("#{deployment_dir}/WestpacOwcImport/WestpacOwcImport-#{build_version}.zip") }
  end

# 6. DOWNLOAD SQL ARTEFACT

  log "Downloading SQL artefacts"

  remote_file "#{deployment_dir}/WestpacOwcSQLs/WestpacOwcSQLs-#{build_version}.zip" do
    source "#{artifactory_url}/WestpacOwcSQLs/#{build_version}/WestpacOwcSQLs-#{build_version}.zip"
    owner 'oracle'
    group 'oinstall'
    mode '0755'
    action :create
  end

  log "Extracting SQL for Deployment"

  bash "Extracting SQL ZIP" do
    code <<-EOH
      cd #{deployment_dir}/WestpacOwcSQLs
      unzip WestpacOwcSQLs-#{build_version}.zip
      chmod -R 755 *
      EOH
    only_if { ::File.exist?("#{deployment_dir}/WestpacOwcSQLs/WestpacOwcSQLs-#{build_version}.zip") }
  end

# 7. Execute SQLs

  if my_topology_vars['dcms']['sql_deploy'] == 'true'
    #Execute DDL
    oracle_sql "#{deployment_dir}/WestpacOwcSQLs/SQL/dcms_ddl.sql" do
      oracle_home "/oracle/app/binaries/#{asset_code}/dbclient"
      db_service_name my_topology_vars["#{asset_code}"]['database']['dcms_service_name']
      db_host my_topology_vars["#{asset_code}"]['database']['scan_address']
      db_port my_topology_vars["#{asset_code}"]['database']['listen_port'].to_i 
      db_username my_topology_vars["#{asset_code}"]['database']['custom_schema']
      db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/OBPIPM").value)
      sql_file "#{deployment_dir}/WestpacOwcSQLs/SQL/dcms_ddl.sql"
      action :run
      user 'oracle'
      group 'oinstall'
    end
    # Execute DML
    oracle_sql "#{deployment_dir}/WestpacOwcSQLs/SQL/dcms_dml.sql" do
      oracle_home "/oracle/app/binaries/#{asset_code}/dbclient"
      db_service_name my_topology_vars["#{asset_code}"]['database']['dcms_service_name']
      db_host my_topology_vars["#{asset_code}"]['database']['scan_address']
      db_port my_topology_vars["#{asset_code}"]['database']['listen_port'].to_i 
      db_username my_topology_vars["#{asset_code}"]['database']['custom_schema']
      db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/OBPIPM").value)
      sql_file "#{deployment_dir}/WestpacOwcSQLs/SQL/dcms_dml.sql"
      action :run
      user 'oracle'
      group 'oinstall'
    end
    # Execute update statement to change DCMSActiveSiteID based on data_center
    oracle_sql "Update SQL to change DCMSActiveSiteID " do
      oracle_home "/oracle/app/binaries/#{asset_code}/dbclient"
      db_service_name my_topology_vars["#{asset_code}"]['database']['dcms_service_name']
      db_host my_topology_vars["#{asset_code}"]['database']['scan_address']
      db_port my_topology_vars["#{asset_code}"]['database']['listen_port'].to_i 
      db_username my_topology_vars["#{asset_code}"]['database']['custom_schema']
      db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/OBPIPM").value)
      sql "update OWC_IMPORT_PROCESS_CONFIG set CONFIG_VALUE = '#{data_center}' where CONFIG_NAME = 'DCMSActiveSiteID'"
      action :run
      user 'oracle'
      group 'oinstall'
    end  
    if my_topology_vars["#{asset_code}"]['hostnameList'].length == 1
      # Execute update statement specific to single node envs.
      oracle_sql "Update SQL TO change DCMSActiveNodeID to UCM_server1" do
        oracle_home "/oracle/app/binaries/#{asset_code}/dbclient"
        db_service_name my_topology_vars["#{asset_code}"]['database']['dcms_service_name']
        db_host my_topology_vars["#{asset_code}"]['database']['scan_address']
        db_port my_topology_vars["#{asset_code}"]['database']['listen_port'].to_i 
        db_username my_topology_vars["#{asset_code}"]['database']['custom_schema']
        db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/OBPIPM").value)
        sql "update OWC_IMPORT_PROCESS_CONFIG set CONFIG_VALUE = 'UCM_server1' where CONFIG_NAME = 'DCMSActiveNodeID'"
        action :run
        user 'oracle'
        group 'oinstall'
      end
    end
  end

# 8. Deploy Component ZIP

  if my_topology_vars['dcms']['component_deploy'] == 'true'
    bash "Deploying Component" do
      code <<-EOH
        cd /oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/ucm/cs/bin
        ./ComponentTool -v --install #{deployment_dir}/WestpacOwcImport/WestpacOwcImport/WestpacOwcImport.zip
        EOH
      only_if { ::File.exist?("#{deployment_dir}/WestpacOwcImport/WestpacOwcImport/WestpacOwcImport.zip") }
    end
  end

end


