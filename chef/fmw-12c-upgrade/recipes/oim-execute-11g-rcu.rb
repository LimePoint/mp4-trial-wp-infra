#Recipe: Recipe to Run the 11g RCU to prepare for upgrade from 11g to 12c. 

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
  end
  if asset_code == 'obpcid'
    asset_code = 'obpcim'
  end
end


# Data bag for target asset must be updated with release_version 1.7.0 and DB details for new DB if applicable.
database_url = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}:#{my_topology_vars["#{asset_code}"]['database']['listen_port']}/#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
dba_username = my_topology_vars["#{asset_code}"]['database']['sysdba_username'].upcase
if ['obpoim','obpcim'].include?(asset_code)
  schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}-MDS").value)
else
  schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}").value)
end  
dba_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{dba_username.upcase}").value)

if release_version != '1.7.0'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

if !['obpoim','obpcim'].include?(asset_code)
  Chef::Log.info ('Does not Apply to this asset, check the asset on which the recipe is run')
  return
end

# OIM specific RCU components
if ['obpoim','obpcim'].include?(asset_code)
  bash 'Create Schemas for OIM 11g' do
    code <<-EOH
      export ORACLE_HOME=/oracle/stage/rcu/11.1.1.9/rcuHome ;
      export JAVA_HOME=/oracle/app/binaries/#{asset_code}/java ;
      export PATH=$JAVA_HOME/bin:$PATH ;
      cd $ORACLE_HOME/bin
      (echo #{dba_password}; echo #{schema_password}) | ./rcu -silent -createRepository -databaseType ORACLE \
      -connectString #{database_url} \
      -dbUser #{dba_username} -dbRole SYSDBA \
      -schemaPrefix #{asset_code} \
      -component SOAINFRA -tempTablespace TEMP \
      -component ORASDPM -tempTablespace TEMP \
      -component OPSS -tempTablespace TEMP \
      -component OIM -tempTablespace TEMP \
      -component MDS -tempTablespace TEMP \
      -component BIPLATFORM -tempTablespace TEMP \
      -useSamePasswordForAllSchemaUsers true
      EOH
  end
end
