require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPCID'
return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####

global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge!(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)
asset_vars = my_topology_vars[_item_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']

#### Add asset specific code here ####
code = _item_code.downcase

password = safe_get_password(password_vault_name, 'database', 'dbsyspassword')
PasswordVault.put_password(password_vault_name, code, asset_vars['database']['sysdba_username'].upcase, password)

password = safe_get_password(password_vault_name, 'all', 'truststorepass')
PasswordVault.put_password(password_vault_name, code, 'truststorepass', password)

password = PasswordVault.get_password(password_vault_name, 'obpcid', 'keystorepass')
PasswordVault.put_password(password_vault_name, code, 'keystorepass', password)

p = PasswordVault.get_password(password_vault_name, 'obpcid', 'healthcheck')
p = PasswordVault.get_password(password_vault_name, 'obpcid', 'readonly')
p = PasswordVault.get_password(password_vault_name, 'obpcid', 'ldapsyncadmin')
p = PasswordVault.get_password(password_vault_name, 'obpcid', 'obpobh_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpcid', 'obposb_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpcid', 'obpsoa_readonly' )

#### End asset specific code      ####

#### Update Oracle Console URLs ####
consoles = [
]


run_mintpress_project!(_item_code.downcase, my_topology_vars, environment_name, password_vault_name, urls: consoles, release_version: asset_vars['release_version'])