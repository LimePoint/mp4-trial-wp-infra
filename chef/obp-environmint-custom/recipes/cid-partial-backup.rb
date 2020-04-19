# Author: Uday B

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

# This file loads the base OBP schema into CID and should be used during the configure online phase of CID build
# This can be run over and over again and it was just ignore the entries.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

cidAdminUsername="cn=orcladmin"
cidAdminPassword=Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/cn=orcladmin").value)
cidNSSLListenPort="17001"

if ::File.exists?('/oracle/app/binaries/obpcid/fmw/idm')
	cidHome="/oracle/app/binaries/obpcid/fmw/idm"
else
	cidHome="/oracle/app/binaries/obpcid/fmw"
end

path_4_ldif_bkp = "/oracle/app/binaries/cid_ldif_backups"
group_dn = "cn=customer,cn=groups,dc=westpac,dc=com,dc=au"
user_dn = "cn=customer,cn=users,dc=westpac,dc=com,dc=au"
resrve_dn = "cn=reserve,dc=westpac,dc=com,dc=au"

Chef::Log.info('Checking LDAP Connectivity')
Chef::Log.info("ORACLE_HOME: #{cidHome}")
Chef::Log.info("LDAP Host: #{node.name}")
Chef::Log.info("LDAP Port: #{cidNSSLListenPort}")
Chef::Log.info("LDAP Username: #{cidAdminUsername}")

package 'openldap-clients'

directory "#{path_4_ldif_bkp}" do
    owner 'oracle'
    group 'oinstall'
    mode '0750'
    action :create
end

bash 'Check CID Connectivity' do
	code <<-EOH
    export ORACLE_HOME="#{cidHome}"
    export LD_LIBRARY_PATH="#{cidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapbind -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword}
	EOH
end

Chef::Log.info("LDAP Connectivity Successful")

Chef::Log.info("Backing up Users and Apps")

bash 'Backup Users, Groups & Resrve' do
	code <<-EOH
    ldapsearch -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword} -s sub -b "#{group_dn}" -o ldif-wrap="no" -L "*" orclguid > "#{path_4_ldif_bkp}/#{environment_code}_cid_cust_groups.ldif"
    ldapsearch -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword} -s sub -b "#{user_dn}" -o ldif-wrap="no" -L "*" orclguid > "#{path_4_ldif_bkp}/#{environment_code}_cid_cust_users.ldif"
    ldapsearch -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword} -s sub -b "#{resrve_dn}" -o ldif-wrap="no" -L "*" orclguid > "#{path_4_ldif_bkp}/#{environment_code}_cid_resrve.ldif"
	EOH
end

Chef::Log.info('Completed backingup users')
