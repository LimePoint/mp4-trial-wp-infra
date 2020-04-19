# Recipe: Recipe to replace FMW 11g home with FMW 12c after upgrade. 

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

if my_topology_vars["#{asset_code}"]['dns_domain_name'] != '.wpdev.mintpress.io' && !['svp3r','prd3r','psp3'].include?(environment_name) && ['obpoid','obpcid'].include?(asset_code)
  if asset_code == 'obpoid'
    asset_code = 'obpoim'
    item_code = 'oim'
  end
  if asset_code == 'obpcid'
    asset_code = 'obpcim'
    item_code = 'cim'
  end
end


domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
admin_domain_home = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}"
managed_domain_home = "/oracle/app/binaries/runtime/#{asset_code}/domains/#{domain_name}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_dir = "/oracle/app/binaries/12c_upgrade"
target_fmw_base = "/oracle/app/binaries/#{asset_code}"
fmw_11g_bkup = "/oracle/app/binaries/#{asset_code}_11g"
temp_12c_base = "/oracle/app/binaries/#{item_code}12c"


if release_version != '1.7.0'
  Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
  return
end

if !['obpoim','obpcim'].include?(asset_code)
  Chef::Log.info ('Does not Apply to this asset, check the asset on which the recipe is run')
  return
end

bash 'Replace temp 12c FMW home path references to default FMW path in common share mount' do
  code <<-EOH
  echo "Check if any java process running"
  java_num=`ps -ef|grep java|grep #{asset_code} | wc -l`
  if [ $java_num -gt 1 ];then
      echo "Appears some java process running, Verify and shut it down to proceed"
      exit 1
  else
    echo "Appears No java process running, proceeding with Replacing FMW 11g home with FMW 12c"
    
    echo "Delete server folders and logs folders"
    rm -rf /oracle/app/logs/#{asset_code}/#{asset_code}_domain;
    rm -rf #{admin_domain_home}/servers/soa_server* #{admin_domain_home}/servers/oim_server*;

    echo "Updating Path in Domain Home"
    cd /oracle/app/runtime/#{asset_code}/domains; 
    grep -lIR "#{temp_12c_base}" | xargs sed -i "s|#{temp_12c_base}|#{target_fmw_base}|g"

    echo "Copy 12c em.ear to correct location and update config.xml"
    
    cp -r #{target_fmw_base}/fmw/user_projects/applications/#{domain_name}/em.ear /oracle/app/runtime/#{asset_code}/domains/applications/#{domain_name}/;
    cd /oracle/app/runtime/#{asset_code}/domains;
    grep -lIR "/oracle/app/binaries/#{asset_code}/fmw/user_projects/applications/#{asset_code}_domain/em.ear" | xargs sed -i "s|/oracle/app/binaries/#{asset_code}/fmw/user_projects/applications/#{asset_code}_domain/em.ear|/oracle/app/runtime/#{asset_code}/domains/applications/#{asset_code}_domain/em.ear|g"
    
    echo "Completed Replacing temp 12c FMW home path references to default FMW path in common share mount"

    touch #{admin_domain_home}/.12c_upgraded;
  fi
  EOH
  not_if { ::File.exist?("#{admin_domain_home}/.12c_upgraded") }
end


bash 'Replace temp 12c FMW home path references to default FMW path in binaries share mount' do
  code <<-EOH
  echo "Check if any java process running"
  java_num=`ps -ef|grep java|grep #{asset_code} | wc -l`
  if [ $java_num -gt 1 ];then
      echo "Appears some java process running, Verify and shut it down to proceed"
      exit 1
  else
    echo "Appears No java process running, proceeding with Replacing FMW 11g home with FMW 12c"
    echo "Moving fmw home from 12c to 11g"
    mv #{target_fmw_base} #{fmw_11g_bkup};
    mv #{temp_12c_base} #{target_fmw_base}
    
    echo "Updating Path in #{target_fmw_base}"
    cd #{target_fmw_base};
    grep -lIR "#{temp_12c_base}" | xargs sed -i "s|#{temp_12c_base}|#{target_fmw_base}|g"

    cd /oracle/app/binaries/#{asset_code}/dbclient/instantclient;
    ln -sf /oracle/app/binaries/#{asset_code}/dbclient/lib/libheteroxa12.so libheteroxa12.so;
    ln -sf /oracle/app/binaries/#{asset_code}/dbclient/lib/libnnz12.so libnnz12.so;
    ln -sf /oracle/app/binaries/#{asset_code}/dbclient/lib/libocci.so.12.1 libocci.so.12.1;
    ln -sf /oracle/app/binaries/#{asset_code}/dbclient/lib/libocijdbc12.so libocijdbc12.so;
    ln -sf /oracle/app/binaries/#{asset_code}/dbclient/jdbc/lib/ojdbc8.jar ojdbc8.jar;
    cd /oracle/app/binaries/#{asset_code}/dbclient/bin;
    ln -sf /oracle/app/binaries/#{asset_code}/dbclient/olap/awm/awm.sh awm;
    
  fi
  EOH
  only_if { ::File.exist?("/oracle/app/binaries/#{item_code}12c") } 
end
