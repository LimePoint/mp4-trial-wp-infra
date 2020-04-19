# Author: Uday B

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

custom_ldif_path = "/oracle/stage/oid_custom_ldif/ocloud_user_config"

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

Chef::Log.info("Loading test Users")

# Ignore failures ?
bash 'Load Test Users' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -a -c -f #{custom_ldif_path}/1_User_Creation.ldif
	EOH
	ignore_failure true
end

Chef::Log.info('Completed loading test users')

Chef::Log.info('Importing application roles and role mappings')

# Ignore failures ?
bash 'Load AppRoles and RoleMappings' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    cd #{custom_ldif_path}/1.4
    for i in `ls [2-7]*`; do
    ldapmodify -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -a -c -f #{custom_ldif_path}/1.4/${i};
    done;
	EOH
	ignore_failure true
end

Chef::Log.info('Completed Importing application roles and role mappings')
