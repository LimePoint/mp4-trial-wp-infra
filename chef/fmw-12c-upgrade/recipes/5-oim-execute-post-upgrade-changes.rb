#Recipe: Recipe to Configure Post 12c Upgrade domain Changes. 
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
domain_home = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}"
managed_domain_home = "/oracle/app/binaries/runtime/#{asset_code}/domains/#{domain_name}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
upgrade_dir = "/oracle/app/binaries/12c_upgrade"
fmw_12c_home = "/oracle/app/binaries/#{item_code}12c/fmw"
fmw_11g_home = "/oracle/app/binaries/#{asset_code}/fmw"
keystore_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/keystorepass").value)
config_file = "#{domain_home}/config/config.xml"
libovd_adapters = "#{domain_home}/config/fmwconfig/ovd/oim/adapters.os_xml"

if release_version != '1.7.0'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

if !['obpoim','obpcim'].include?(asset_code)
  Chef::Log.info ('Does not Apply to this asset, check the asset on which the recipe is run')
  return
end


execute "backup config.xml" do
  command "cp #{config_file} #{config_file}.mint"
  cwd "#{domain_home}/config"
  puts "Backing up #{config_file} to #{config_file}.mint"
  not_if { File.exists?(config_file + '.mint') }
end


bash 'Update 12c Libraries versions' do
  code <<-EOH
    cd #{domain_home}/config;
    sed -i 's|com.oracle.cie.comdev#3.0.0.0@7.8.2.0|com.oracle.cie.comdev#3.0.0.0@7.8.4.0|g; s|com.oracle.cie.comdev_7.8.2.0.jar|com.oracle.cie.comdev_7.8.4.0.jar|g; s|com.oracle.cie.xmldh#2.0.0.0@3.4.2.0|com.oracle.cie.xmldh#2.0.0.0@3.4.4.0|g; s|com.oracle.cie.xmldh_3.4.2.0.jar|com.oracle.cie.xmldh_3.4.4.0.jar|g' config.xml
    EOH
end

if asset_code == 'obpcim'
  execute "backup LibOVD adapters" do
  command "cp #{libovd_adapters} #{libovd_adapters}.mint"
  cwd "#{domain_home}/config/fmwconfig/ovd/oim"
  puts "Backing up #{libovd_adapters} to #{libovd_adapters}.mint"
  not_if { File.exists?(libovd_adapters + '.mint') }
 end
end

bash 'Enable TLS Ciphers for LibOVD' do
  code <<-EOH
  export NEW_CIPHER="<cipherSuites>\\n             <cipher>TLS_RSA_WITH_AES_256_CBC_SHA256</cipher>"
  if grep TLS_RSA_WITH_AES_256_CBC_SHA256 #{libovd_adapters}; then
    echo 'Cipher - TLS_RSA_WITH_AES_256_CBC_SHA256 already exists'
  else
    sed -i "s#<cipherSuites>#\$NEW_CIPHER#g" #{libovd_adapters};
    echo 'Added Ciper TLS_RSA_WITH_AES_256_CBC_SHA256 Successfully'
  fi
  EOH
  only_if { File.exists?(libovd_adapters) }
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

    #Configure 12c NodeManager
    echo "Configure 12c NodeManager Properties"
    mkdir -p #{fmw_12c_home}/wlserver/common/nodemanager;
    cp -v #{fmw_11g_home}/wlserver_10.3/common/nodemanager/nodemanager.* #{fmw_12c_home}/wlserver/common/nodemanager/;
    cd #{fmw_12c_home}/wlserver/common/nodemanager/;
    cp -v #{fmw_12c_home}/wlserver/common/nodemanager/nodemanager.properties #{fmw_12c_home}/wlserver/common/nodemanager/nodemanager.properties.b4.12c.update.$(date +"%Y%m%d_%H%M%S");
    sed -i 's|PropertiesVersion.*$|PropertiesVersion=12.2.1.3.0|' nodemanager.properties;
    sed -i 's|#{fmw_11g_home}/wlserver_10.3|#{fmw_12c_home}/wlserver|g' nodemanager.properties;
    sed -i 's|CustomIdentityKeyStorePassPhrase.*$|CustomIdentityKeyStorePassPhrase=#{keystore_password}|g; s|CustomIdentityPrivateKeyPassPhrase.*$|CustomIdentityPrivateKeyPassPhrase=#{keystore_password}|g' nodemanager.properties;
    echo "Completed Configure 12c NodeManager Properties"
    EOH
end


