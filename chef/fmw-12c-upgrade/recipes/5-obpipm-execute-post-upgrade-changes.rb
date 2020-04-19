#Recipe: Recipe to Configure Post 12c Upgrade domain Changes. 
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
if item_code == 'ucm'
  item_code = 'ipm'
end
asset_code = "obp#{item_code}"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
admin_domain_home = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}"
managed_domain_home = "/oracle/app/binaries/runtime/#{asset_code}/domains/#{domain_name}"
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_log_dir = "/oracle/app/binaries/12c_upgrade"
dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase
fmw_12c_home = "/oracle/app/binaries/#{item_code}12c/fmw"
fmw_11g_home = "/oracle/app/binaries/#{asset_code}/fmw"
keystore_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/keystorepass").value)
ucmVaultDir = "/oracle/app/runtime/#{asset_code}/#{environment_name}/ucm/cs"


if release_version != '1.7.0'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

if asset_code != 'obpipm'
  Chef::Log.info ('Doesnt Apply to this asset, check the asset on which the recipe is run')
  return
end

bash 'Perform post upgrade changes' do
  code <<-EOH
    #Setting WLST Property
    echo "Setting WLST Property"
    if grep CustomTrustKeyStoreFileName #{fmw_12c_home}/oracle_common/common/bin/commBaseEnv.sh;then
      echo 'WLST Property Exists'
    else
      cp -pv #{fmw_12c_home}/oracle_common/common/bin/commBaseEnv.sh #{fmw_12c_home}/oracle_common/common/bin/commBaseEnv.sh.bkp.b4.12cupgrade.$(date +"%Y%m%d_%H%M%S")
      echo "WLST_PROPERTIES=\\"\\${WLST_PROPERTIES} -Djava.security.egd=file:///dev/urandom -Dweblogic.security.SSL.enableJSSE=true -Dweblogic.security.SSL.ignoreHostnameVerification=true -Dweblogic.security.TrustKeyStore=CustomTrust -Dweblogic.security.CustomTrustKeyStoreFileName=/oracle/app/runtime/#{environment_name}/certs/WBCTrust.jks -Djavax.net.ssl.trustStore=/oracle/app/runtime/#{environment_name}/certs/WBCTrust.jks -Dweblogic.security.TrustKeystoreType=jks\\" ; export WLST_PROPERTIES" >> #{fmw_12c_home}/oracle_common/common/bin/commBaseEnv.sh
    fi
    echo "Completed setting WLST Property"

    #Removing cache and tmp
    echo "Removing cache and tmp"
    find #{admin_domain_home}/servers/ -name tmp -o -name cache -type d | xargs rm -rf;
    if [ -d "/oracle/app/binaries/runtime" ]; then
      find #{managed_domain_home}/servers/ -name tmp -o -name cache -type d | xargs rm -rf;
    fi
    echo "Completed cleaning up cache and tmp directories"

    #Configure 12c NodeManager
    echo "Configure 12c NodeManager Properties"
    mkdir -p #{fmw_12c_home}/wlserver/common/nodemanager;
    cp -v #{fmw_11g_home}/wlserver_10.3/common/nodemanager/nodemanager.* #{fmw_12c_home}/wlserver/common/nodemanager/;
    cd #{fmw_12c_home}/wlserver/common/nodemanager/;
    cp -v #{fmw_12c_home}/wlserver/common/nodemanager/nodemanager.properties #{fmw_12c_home}/wlserver/common/nodemanager/nodemanager.properties.b4.12c.update.$(date +"%Y%m%d_%H%M%S");
    sed -i 's|PropertiesVersion.*$|PropertiesVersion=12.2.1.3.0|' nodemanager.properties;
    sed -i 's|#{fmw_11g_home}/wlserver_10.3|#{fmw_12c_home}/wlserver|g' nodemanager.properties;
    sed -i 's|CustomIdentityKeyStorePassPhrase.*$|CustomIdentityKeyStorePassPhrase=#{keystore_password}|g; s|CustomIdentityPrivateKeyPassPhrase.*$|CustomIdentityPrivateKeyPassPhrase=#{keystore_password}|g' nodemanager.properties;
    sed -i 's|obpipm_domain.*$|obpipm_domain=#{managed_domain_home};#{admin_domain_home}|g' nodemanager.domains; 
    echo "Completed Configure 12c NodeManager Properties"
    EOH
    not_if { ::File.exist?("#{managed_domain_home}/.12c_upgraded") }
end

bash 'Pack Unpack Domain' do
  code <<-EOH
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    SET='\033[0m'
    cd /oracle/app/runtime;
    if [ -f "obpipm_domain_pack.jar" ]; then
      echo "Domain pack jar Exists... Skipping packing the domain..."
    else
      #{fmw_12c_home}/oracle_common/common/bin/pack.sh -managed=true -domain=#{admin_domain_home} -template=obpipm_domain_pack.jar -template_name="admin_obpipm_domain";
    fi
    if [ $? -ne 0 ]; then
      echo -e "###############################################################################################\n" 
      echo -e "${RED}Domain Pack Failed, Check the Logs and troubleshoot the issue"
      echo -e "\n#############################################################################################\n"
        exit 1
    else
      touch /oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/.12c_upgraded;
      echo -e "###############################################################################################\n"
      echo -e "${GREEN} Domain Pack completed successfully"
      echo -e "\n#############################################################################################\n"
    fi

    #Backup existing managed Domain home before Unpacking the domain
    if [ -f "/oracle/app/binaries/runtime/#{asset_code}/bkp_pre_reconfig_domains.tar.gz" ]; then
      echo "One backup already exists... Skipping The backup"
    else
      cd /oracle/app/binaries/runtime/#{asset_code};
      echo "Backing up domains directory"
      tar -czf bkp_pre_reconfig_domains.tar.gz domains;
    fi

    # Unpack The Domain
    cd /oracle/app/runtime;
    #{fmw_12c_home}/oracle_common/common/bin/unpack.sh -domain=/oracle/app/binaries/runtime/obpipm/domains/obpipm_domain -template=obpipm_domain_pack.jar -overwrite_domain=true
    if [ $? -ne 0 ]; then
      echo -e "###############################################################################################\n" 
      echo -e "${RED}Domain Unpack Failed, Check the Logs and troubleshoot the issue"
      echo -e "\n#############################################################################################\n"
      exit 1
    else
      touch /oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/.12c_upgraded;
      echo -e "###############################################################################################\n"
      echo -e "${GREEN} Domain Unpack completed successfully Review the logs located at #{upgrade_log_dir}.${SET}"
      echo -e "\n#############################################################################################\n"
    fi

    echo "Deleting 11g specific configuration files after Unpack "
    cd #{managed_domain_home}/config;
    find . -name JOCConfig_mbeans.xml -o -name webservices.mgmt-mbeans.xml -type f | xargs rm -rvf;
    echo "Update filepaths in UCM Config";
    if [ -d #{managed_domain_home}/ucm ]; then
      cd #{managed_domain_home}/ucm/cs/bin;
      sed -i 's|#{fmw_11g_home}/wcc_11.1|#{fmw_12c_home}/wccontent|g' intradoc.cfg;
    fi
    EOH
    not_if { ::File.exist?("#{managed_domain_home}/.12c_upgraded") }
end


#Replace temp 12c home path with default FMW home path in common share location
bash "Replace temp 12c home path with default FMW home path in common share location" do
  code <<-EOH
  
  echo "Removing cache and tmp"
  find #{admin_domain_home}/servers/ -name tmp -o -name cache -type d | xargs rm -rf;
  echo "Completed cleaning up cache and tmp directories"

  if [ -d "/oracle/app/binaries/obpipm_11g" ]; then
    echo "Replace Already done, Skipping.."
  else
    echo "Find and replace temp 12c home path with default FMW home path  in /oracle/app/runtime/obpipm";
    cd /oracle/app/runtime/obpipm;
    grep -lIR '/oracle/app/binaries/#{item_code}12c' | xargs sed -i 's|/oracle/app/binaries/#{item_code}12c|/oracle/app/binaries/obpipm|g';
    
    echo "Update links"
    cd #{ucmVaultDir}/admin/bin;
    ln -sf /oracle/app/binaries/obpipm/fmw/wccontent/ucm/idc/native/Launcher.sh Launcher.sh;
  fi

  echo "Replace temp 12c FMW path in ucm config files"
  cd #{ucmVaultDir};
  cp -pv data/providers/embeddedldap/provider.hda data/providers/embeddedldap/provider.hda.bkp.11g.$(date +"%Y%m%d_%H%M%S");
  cp -pv data/users/SecurityInfo.hda data/users/SecurityInfo.hda.bkp.11g.$(date +"%Y%m%d_%H%M%S");
  sed -i 's|#{fmw_11g_home}|#{fmw_12c_home}|g' data/providers/embeddedldap/provider.hda;
  sed -i 's|#{fmw_11g_home}/wcc_11.1|#{fmw_12c_home}/wccontent|g' data/users/SecurityInfo.hda;  
  touch #{admin_domain_home}/.12c_upgraded
  EOH
  not_if { ::File.exist?("#{admin_domain_home}/.12c_upgraded") }
end

#Replace temp 12c home path with default FMW home path in binaries mount
bash "Replace temp 12c home path with default FMW home path in binaries mount" do
  code <<-EOH
  if [ -d "/oracle/app/binaries/runtime" ]; then
    find #{managed_domain_home}/servers/ -name tmp -o -name cache -type d | xargs rm -rf;
  fi
  echo "Completed cleaning up cache and tmp directories"

  if [ -d "/oracle/app/binaries/obpipm_11g" ]; then
    echo "Replace Already done, Skipping.."
  else
    echo "Replace temp 12c home path with default FMW home path"
    mv -v /oracle/app/binaries/obpipm /oracle/app/binaries/obpipm_11g;
    mv -v /oracle/app/binaries/#{item_code}12c /oracle/app/binaries/obpipm;

    echo "Find and replace temp 12c home path in /oracle/app/binaries/runtime/obpipm/domains"
    cd /oracle/app/binaries/runtime/obpipm/domains;
    grep -lIR '/oracle/app/binaries/#{item_code}12c' | xargs sed -i 's|/oracle/app/binaries/#{item_code}12c|/oracle/app/binaries/obpipm|g';
    
    echo "Find and replace temp 12c home path in /oracle/app/binaries/obpipm"
    cd /oracle/app/binaries/obpipm;
    grep -lIR '/oracle/app/binaries/#{item_code}12c' | xargs sed -i 's|/oracle/app/binaries/#{item_code}12c|/oracle/app/binaries/obpipm|g';
    
    echo "Update links"
    if [ -d #{managed_domain_home}/ucm ]; then
      cd #{managed_domain_home}/ucm/cs/bin;
      ln -sf /oracle/app/binaries/obpipm/fmw/wccontent/ucm/idc/native/Launcher.sh Launcher.sh;
      cd /oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/ucm/cs/admin/bin;
      ln -sf /oracle/app/binaries/obpipm/fmw/wccontent/ucm/idc/native/Launcher.sh Launcher.sh;
    fi;
    cd /oracle/app/binaries/obpipm/dbclient/instantclient;
    ln -sf /oracle/app/binaries/obpipm/dbclient/lib/libheteroxa12.so libheteroxa12.so;
    ln -sf /oracle/app/binaries/obpipm/dbclient/lib/libnnz12.so libnnz12.so;
    ln -sf /oracle/app/binaries/obpipm/dbclient/lib/libocci.so.12.1 libocci.so.12.1;
    ln -sf /oracle/app/binaries/obpipm/dbclient/lib/libocijdbc12.so libocijdbc12.so;
    ln -sf /oracle/app/binaries/obpipm/dbclient/jdbc/lib/ojdbc8.jar ojdbc8.jar;
    cd /oracle/app/binaries/obpipm/dbclient/bin;
    ln -sf /oracle/app/binaries/obpipm/dbclient/olap/awm/awm.sh awm;
    echo "Rename and replace of 12c and 11g FMW Homes completed"
  fi
  EOH
end
