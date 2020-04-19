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

cidAdminUsername="cn=orcladmin"
cidAdminPassword=Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/cn=orcladmin").value)

cidNSSLListenPort="17001"
if ::File.exists?('/oracle/app/binaries/obpcid/fmw/idm')
  cidHome="/oracle/app/binaries/obpcid/fmw/idm"
else
  cidHome="/oracle/app/binaries/obpcid/fmw"
end

Chef::Log.info('Checking LDAP Connectivity')
Chef::Log.info("ORACLE_HOME: #{cidHome}")
Chef::Log.info("LDAP Host: #{node.name}")
Chef::Log.info("LDAP Port: #{cidNSSLListenPort}")
Chef::Log.info("LDAP Username: #{cidAdminUsername}")

bash 'Check OID Connectivity' do
    code <<-EOH
    export ORACLE_HOME="#{cidHome}"
    export LD_LIBRARY_PATH="#{cidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapbind -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword}
    EOH
end

Chef::Log.info("LDAP Connectivity Successful")

Chef::Log.info("Writing Schema file")

template 'cid-schema-load.ldif' do
  source "ldif/fmw/cid-schema-load.ldif.erb"
  path "#{cidHome}/#{environment_code}_cid-schema-load.ldif"
  mode '0700'
end

Chef::Log.info('Importing LDAP Schema for OBP')

# Ignore failures ?
bash 'Load CID Schema' do
  code <<-EOH
    export ORACLE_HOME="#{cidHome}"
    export LD_LIBRARY_PATH="#{cidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword} -a -c -f #{cidHome}/#{environment_code}_cid-schema-load.ldif
    EOH
   ignore_failure true 
end

Chef::Log.info('LDAP Schema Import Complete')

# Generate ldif for content
template 'cid-content-load.ldif' do
  source "ldif/fmw/cid-content-load.ldif.erb"
  path "#{cidHome}/#{environment_code}_cid-content-load.ldif"
  variables(
      :healthcheck => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/healthcheck").value),
      :readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/readonly").value),
      :ldapsyncadmin => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/ldapsyncadmin").value),
      :obpobh_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/obpobh_readonly").value),
      :obposb_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/obposb_readonly").value),
      :obpsoa_readonly => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpcid/obpsoa_readonly").value)
  )
  mode '0700'
end

Chef::Log.info('Importing LDAP Objects for OBP')

# Ignore failures ?
bash 'Load OID Objects' do
  code <<-EOH
    export ORACLE_HOME="#{cidHome}"
    export LD_LIBRARY_PATH="#{cidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword} -a -c -f #{cidHome}/#{environment_code}_cid-content-load.ldif
    rm -f #{cidHome}/#{environment_code}_cid-content-load.ldif
    EOH
   ignore_failure true 
end

Chef::Log.info('LDAP Object Import Complete')

Chef::Log.info('Executing OID policies.')

template 'cid-configs.ldif' do
    source "ldif/fmw/cid-configs.ldif.erb"
    path "#{cidHome}/#{environment_code}_cid-configs.ldif"
    mode '0700'
end

bash 'OID Policy Updates' do
    code <<-EOH
    export ORACLE_HOME="#{cidHome}"
    export LD_LIBRARY_PATH="#{cidHome}/lib"
    export PATH="$ORACLE_HOME/bin:$PATH"
    ldapmodify -h #{node.name} -p #{cidNSSLListenPort} -D #{cidAdminUsername} -w #{cidAdminPassword} -a -c -f #{cidHome}/#{environment_code}_cid-configs.ldif
    EOH
    ignore_failure true 
end
Chef::Log.info('OID policies updated.')

