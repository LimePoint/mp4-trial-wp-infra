# Author: Harsha Gurram

# Recipe to reset coherence keystore for stronger security and post patching (July 2018 PSU) step [to run the script - softlockEnableDisable.py]

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']


asset_code = "obpoam"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
keystorePassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/keystorepass").value)
keystore_loc = '/oracle/app/runtime/obpoam/domains/obpoam_domain/config/fmwconfig'
tmp_dir = '/oracle/app/binaries/obpoam/tmp'


template 'Template Coherence Keystore pwd Reset Script' do
  source "fmw/wlst/reset_coh_keystore.py.erb"
  path "#{tmp_dir}/reset_coh_keystore.py"
  mode '0700'
end

bash 'Executing Coherence Keystore Reset' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/iam_11.1/common/bin/wlst.sh #{tmp_dir}/reset_coh_keystore.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} #{keystorePassword}
    EOH
    not_if { ::File.exist?("#{keystore_loc}/.cohstore.jks.mint") }
end

bash 'Recreating Coherence Keystore with Stronger key' do
  code <<-EOH
    mv #{keystore_loc}/.cohstore.jks #{keystore_loc}/.cohstore.jks.mint
    /oracle/app/binaries/obpoam/java/bin/keytool -genkey -alias admin -keyalg RSA -keysize 2048 -dname \"CN=\\\"administrator ou=oam\\\", O=Oracle, C=US\" -validity 3650 -keypass #{keystorePassword} -keystore #{keystore_loc}/.cohstore.jks  -storetype JKS -storepass #{keystorePassword}

	/oracle/app/binaries/obpoam/java/bin/keytool -export -alias admin -file #{tmp_dir}/cohadmin.cert -keystore #{keystore_loc}/.cohstore.jks -storepass #{keystorePassword} -storetype jks

	/oracle/app/binaries/obpoam/java/bin/keytool -importcert -noprompt -alias assertion-cert -trustcacerts -file #{tmp_dir}/cohadmin.cert -keystore #{keystore_loc}/.cohstore.jks -storetype JKS -storepass #{keystorePassword}

	/bin/rm -f #{tmp_dir}/cohadmin.cert
    EOH
    not_if { ::File.exist?("#{keystore_loc}/.cohstore.jks.mint") }
    Chef::Log.info('Recreated Stronger Coherence Keystore')
end

bash 'Cleaning cache and tmp of managed servers' do
  code <<-EOH
    rm -rvf #{keystore_loc}/../../servers/*_server*/tmp
    rm -rvf #{keystore_loc}/../../servers/*_server*/cache
    rm -rvf #{keystore_loc}/../../servers/*_server*/stage
    rm -rvf #{keystore_loc}/../../servers/oam_policy_mgr*/tmp
    rm -rvf #{keystore_loc}/../../servers/oam_policy_mgr*/cache
    rm -rvf #{keystore_loc}/../../servers/oam_policy_mgr*/stage
    EOH
end
