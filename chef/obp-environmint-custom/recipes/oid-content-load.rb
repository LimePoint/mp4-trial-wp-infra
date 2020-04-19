# Author: Romil Bhagat

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

# This file loads the base OBP schema into OID and should be used during the configure online phase of OID build
# This can be run over and over again and it was just ignore the entries.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

oidAdminUsername="cn=orcladmin"
oidAdminPassword=Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/cn=orcladmin").value)

oidNSSLListenPort="17001"

if ::File.exists?('/oracle/app/binaries/obpoid/fmw/idm')
	oidHome="/oracle/app/binaries/obpoid/fmw/idm"
else
	oidHome="/oracle/app/binaries/obpoid/fmw"
end

Chef::Log.info('Checking LDAP Connectivity')
Chef::Log.info("ORACLE_HOME: #{oidHome}")
Chef::Log.info("LDAP Host: #{node.name}")
Chef::Log.info("LDAP Port: #{oidNSSLListenPort}")
Chef::Log.info("LDAP Username: #{oidAdminUsername}")

bash 'Check OID Connectivity' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapbind -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword}
	EOH
end

Chef::Log.info("LDAP Connectivity Successful")

Chef::Log.info("Writing Schema file")

template 'oid-schema-load.ldif' do
	source "ldif/fmw/oid-schema-load.ldif.erb"
	path "#{oidHome}/#{environment_code}_oid-schema-load.ldif"
	mode '0700'
end

Chef::Log.info('Importing LDAP Schema for OBP')

# Ignore failures ?
bash 'Load OID Schema' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -a -c -f #{oidHome}/#{environment_code}_oid-schema-load.ldif
	EOH
	ignore_failure true
end

Chef::Log.info('LDAP Schema Import Complete')

# Generate ldif for content
template 'oid-content-load.ldif' do
	source "ldif/fmw/oid-content-load.ldif.erb"
	path "#{oidHome}/#{environment_code}_oid-content-load.ldif"
	variables(
		:OFSSUser => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/OFSSUser").value),
		:offlineuser => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/offlineuser").value),
		:atmuser => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/atmuser").value),
		:posuser => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/posuser").value),
		:obpsoa_admin => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpsoa_admin").value),
		:obpbip_admin => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpbip_admin").value),
		:obpipm_admin => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpipm_admin").value),
		:documaker => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/documaker").value),
		:SA_DOCUMAKER_IPM_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_DOCUMAKER_IPM_MANAGE_USER").value),
		:SA_DOCUMAKER_OBP_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_DOCUMAKER_OBP_MANAGE_USER").value),
		:SA_DLM_API_OSB_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_DLM_API_OSB_USER").value),
		:SA_VALEX_API_OSB_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_VALEX_API_OSB_USER").value),
		:SA_OBP_OSB_APIGATEWAY_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OBP_OSB_APIGATEWAY_USER").value),
		:healthcheck => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/healthcheck").value),
		:readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/readonly").value),
		:obphost_admin => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obphost_admin").value),
		:SA_HOST_SOA_ADMIN_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_HOST_SOA_ADMIN_USER").value),
		:SA_OBP_IPM_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OBP_IPM_MANAGE_USER").value),
		:SA_OBP_BAM_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OBP_BAM_MANAGE_USER").value),
		:SA_OBP_BIP_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OBP_BIP_MANAGE_USER").value),
		:DCMS_OWC_IMPORT_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/DCMS_OWC_IMPORT_USER").value),
		:SA_CONFIGUPLOADER_OBP_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_CONFIGUPLOADER_OBP_USER").value),
		:SA_BATCH_OBP_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_BATCH_OBP_USER").value),
		:SA_OCH_OBP_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OCH_OBP_MANAGE_USER").value),
		:SA_ESIGN_OSB_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_ESIGN_OSB_USER").value),
		:SA_SAM_PARTY_ONBOARD_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_SAM_PARTY_ONBOARD_USER").value),
		:SA_OBP_RULE_INTRODUCER_MANAGER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OBP_RULE_INTRODUCER_MANAGER").value),
		:SA_RB_OSB_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_RB_OSB_USER").value),
		:SA_MEDB_OBP_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_MEDB_OBP_MANAGE_USER").value),
		:SA_OBP_PROCESS_UPGRADE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_OBP_PROCESS_UPGRADE_USER").value),
		:SA_DIGITAL_OBP_MANAGE_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_DIGITAL_OBP_MANAGE_USER").value),
		:SA_API_LENDING_OBP_USER => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/SA_API_LENDING_OBP_USER").value),
		:obpbip_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpbip_readonly").value),
		:obpdoc_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpdoc_readonly").value),
		:obpipm_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpipm_readonly").value),
		:obpurm_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpurm_readonly").value),
		:obpobh_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpobh_readonly").value),
		:obpobu_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpobu_readonly").value),
		:obposb_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obposb_readonly").value),
		:obpsoa_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpsoa_readonly").value)
	)
	mode '0700'
end

Chef::Log.info('Importing LDAP Objects for OBP')

# Ignore failures ?
bash 'Load OID Objects' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -a -c -f #{oidHome}/#{environment_code}_oid-content-load.ldif
    rm -f #{oidHome}/#{environment_code}_oid-content-load.ldif
	EOH
	ignore_failure true
end

Chef::Log.info('LDAP Object Import Complete')

Chef::Log.info('Executing OID policies.')

template 'oid-configs.ldif' do
	source "ldif/fmw/oid-configs.ldif.erb"
	path "#{oidHome}/#{environment_code}_oid-configs.ldif"
	mode '0700'
end

bash 'OID Policy Updates' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -a -c -f #{oidHome}/#{environment_code}_oid-configs.ldif
	EOH
	ignore_failure true
end
Chef::Log.info('OID policies updated.')

if is_running_on_cloud
    include_recipe "::oid-custom-ldif-load"
end
