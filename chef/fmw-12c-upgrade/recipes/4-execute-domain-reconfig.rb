#Recipe: Recipe to Reconfigure Domain from 11g to 12c. 
# Author: Harsha Gurram

require 'tempfile'
require 'base64'
require 'nokogiri'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
if item_code == 'ucm'
  item_code = 'ipm'
end
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
database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_log_dir = "/oracle/app/binaries/12c_upgrade"
fmw_12c_home = "/oracle/app/binaries/#{item_code}12c/fmw"
dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase
if ['obpoim','obpcim'].include?(asset_code)
  schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}-MDS").value)
else
  schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}").value)
end  
dba_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{dba_username.upcase}").value)
admin_config_file = "#{admin_domain_home}/config/config.xml"
managed_config_file = "#{managed_domain_home}/config/config.xml"

if release_version != '1.7.0'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

bash 'Backup Domain before Reconfiguration' do
  code <<-EOH
    echo "Deleting cache and tmp directories before backing up"
    cd #{admin_domain_home}/servers;
    find #{admin_domain_home}/servers -name tmp -o -name cache -type d | xargs rm -rf;
    cd /oracle/app/runtime/#{asset_code};
    echo "Backing up domains directory"
    tar -czf bkp_pre_reconfig_domains.tar.gz domains;
    EOH
    not_if { ::File.exist?("/oracle/app/runtime/#{asset_code}/bkp_pre_reconfig_domains.tar.gz") }
end

# Remove Custom Audit Provider SIEMAuditor. Without doing this the Domain Reconfiguration fails
config_files = [ admin_config_file , managed_config_file ]
# for config_file in config_files do
config_files.each do | config_file |
  ruby_block "Removing Custom SIEM Auditor in #{config_file}" do
    block do
        Chef::Log.info("Inspecting #{config_file}")

        doc = Nokogiri::XML(File.open(config_file))

        exists = doc.at_xpath("//sec:auditor")
        if exists.nil?
            Chef::Log.info("Custom SIEM Auditor is not configured in #{config_file}")
        else
          doc.xpath("//sec:auditor").remove
        end
        File.write(config_file, doc.to_xml)
    end
    only_if { File.exists?(config_file) }
  end
end


# OIM specific tasks
if ['obpoim','obpcim'].include?(asset_code)
  bash 'Cleanup 11g OIM jars' do
    code <<-EOH
      cd /oracle/app/binaries/#{asset_code}/fmw/wlserver_10.3/server/lib/mbeantypes/; 
      rm -f OIMAuthenticator.jar oimsigmbean.jar oimsignaturembean.jar oimmbean.jar
      EOH
  end
end

template "Processing #{asset_code}_domain_reconfig.py" do
	source "domain_reconfig.py.erb"
	path "#{upgrade_log_dir}/#{asset_code}_domain_reconfig.py"
	variables(
		:domain_home => admin_domain_home,
    :wls_admin_pwd => weblogicAdminPassword,
		:db_url => database_url,
		:rcu_prefix => asset_code,
    :schema_password => schema_password
	)
	mode '0644'
	user 'oracle'
	group 'oinstall'
end


bash 'Execute 12c Domain Reconfiguration Script ' do
  code <<-EOH
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    SET='\033[0m'
  	echo "Running Domain Reconfiguration Script"
  	cd #{fmw_12c_home}/oracle_common/common/bin;
    ./wlst.sh #{upgrade_log_dir}/#{asset_code}_domain_reconfig.py
  	if [ $? -ne 0 ]; then
      echo -e "##########################################################################################################################################################\n" 
  		echo -e "${RED}Domain Reconfiguration Failed, Check the Logs located at #{upgrade_log_dir} ${SET}"
      echo -e "\n##########################################################################################################################################################\n"
      	exit 1
    else
      echo -e "##########################################################################################################################################################\n"
    	echo -e "${GREEN} Domain Reconfiguration completed successfully for the domain located at - #{admin_domain_home}. Review the logs located at #{upgrade_log_dir} and verify successful exeuction before proceeding to next step.${SET}"
      echo -e "\n##########################################################################################################################################################\n"
    fi
    EOH
    only_if { ::File.exist?("#{upgrade_log_dir}/#{asset_code}_domain_reconfig.py") }
end
