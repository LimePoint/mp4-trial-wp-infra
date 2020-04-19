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

path_4_ldif_bkp = "/oracle/app/binaries/oid_ldif_backups"
users_dn = "cn=Users, dc=westpac,dc=com,dc=au"
apps_dn = "ou=apps,dc=westpac,dc=com,dc=au"

Chef::Log.info('Checking LDAP Connectivity')
Chef::Log.info("ORACLE_HOME: #{oidHome}")
Chef::Log.info("LDAP Host: #{node.name}")
Chef::Log.info("LDAP Port: #{oidNSSLListenPort}")
Chef::Log.info("LDAP Username: #{oidAdminUsername}")

package 'openldap-clients'

directory "#{path_4_ldif_bkp}" do
    owner 'oracle'
    group 'oinstall'
    mode '0750'
    action :create
end

bash 'Check OID Connectivity' do
	code <<-EOH
    export ORACLE_HOME="#{oidHome}"
    export LD_LIBRARY_PATH="#{oidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapbind -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword}
	EOH
end

Chef::Log.info("LDAP Connectivity Successful")

Chef::Log.info("Backing up Users and Apps")

bash 'Backup Users & Apps' do
	code <<-EOH
    ldapsearch -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -s sub -b "#{users_dn}" -o ldif-wrap="no" -L "*" orclguid > "#{path_4_ldif_bkp}/#{environment_code}_oid_Users.ldif"
    ldapsearch -h #{node.name} -p #{oidNSSLListenPort} -D #{oidAdminUsername} -w #{oidAdminPassword} -s sub -b "#{apps_dn}" -o ldif-wrap="no" -L "*" orclguid > "#{path_4_ldif_bkp}/#{environment_code}_oid_Apps.ldif"
	EOH
end

Chef::Log.info('Completed backingup users')
