#Recipe: Recipe to prep and check readiness for 12c upgrade. 
# Author: Harsha Gurram

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
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_log_dir = "/oracle/app/binaries/12c_upgrade"
fmw_11g_home = "/oracle/app/binaries/#{asset_code}/fmw"
fmw_12c_home = "/oracle/app/binaries/#{item_code}12c/fmw"
dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase


if release_version != '1.7.0'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

if !['obpoim','obpcim'].include?(asset_code)
  Chef::Log.info ('Does not Apply to this asset, check the asset on which the recipe is run')
  return
end


template "Processing #{asset_code}_domain_upgrade.rsp" do
	source "#{asset_code}_domain_upgrade.rsp.erb"
	path "#{upgrade_log_dir}/#{asset_code}_domain_upgrade.rsp"
	variables(
		:domain_home => admin_domain_home,
    :source_fmw_home => fmw_11g_home
	)
	mode '0644'
	user 'oracle'
	group 'oinstall'
end


bash 'Execute Domain Upgrade' do
  code <<-EOH
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    SET='\033[0m'
    echo "Running Domain Upgrade"
    cd #{fmw_12c_home}/oracle_common/upgrade/bin;
    ./ua -configUpgrade -logDir #{upgrade_log_dir} -response #{upgrade_log_dir}/#{asset_code}_domain_upgrade.rsp;
    if [ $? -ne 0 ]; then 
      echo -e "${RED}Domain Upgrade Failed, Check the Logs${SET}"
        exit 1
    else
      echo -e "##########################################################################################################################################################\n"
      echo -e "${GREEN}DOMAIN UPGRADE completed successfully for the domain located at - #{admin_domain_home}. Review the logs located at #{upgrade_log_dir} and ensure that the overall result is a success before proceeding to next step.${SET}"
      echo -e "\n##########################################################################################################################################################\n"
    fi
    EOH
    only_if { ::File.exist?("#{upgrade_log_dir}/#{asset_code}_domain_upgrade.rsp") }
end


