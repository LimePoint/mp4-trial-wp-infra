require 'tempfile'
require 'base64'
require 'net/ssh'
require 'net/sftp'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPOID'
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

password = PasswordVault.get_password(password_vault_name, 'obpoid', 'keystorepass')
PasswordVault.put_password(password_vault_name, code, 'keystorepass', password)

# Create the passwords here else it would fail from the node

p = PasswordVault.get_password(password_vault_name, 'obpoid', 'OFSSUser')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'offlineuser')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'atmuser')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'posuser')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpsoa_admin')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpbip_admin')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpipm_admin')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obphost_admin')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'documaker')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_DOCUMAKER_IPM_MANAGE_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_DOCUMAKER_OBP_MANAGE_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OBP_OSB_APIGATEWAY_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'healthcheck')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_VALEX_API_OSB_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_DLM_API_OSB_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_HOST_SOA_ADMIN_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OBP_IPM_MANAGE_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OBP_BAM_MANAGE_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OBP_BIP_MANAGE_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'DCMS_OWC_IMPORT_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_CONFIGUPLOADER_OBP_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_BATCH_OBP_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OCH_OBP_MANAGE_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_ESIGN_OSB_USER')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_SAM_PARTY_ONBOARD_USER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OBP_RULE_INTRODUCER_MANAGER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_DIGITAL_OBP_MANAGE_USER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_RB_OSB_USER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_MEDB_OBP_MANAGE_USER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_OBP_PROCESS_UPGRADE_USER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'SA_API_LENDING_OBP_USER' )
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpbip_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpdoc_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpobh_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpobu_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpsoa_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpipm_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obpurm_readonly')
p = PasswordVault.get_password(password_vault_name, 'obpoid', 'obposb_readonly')

#### End asset specific code      ####

#### Update Oracle Console URLs ####
consoles = [
]

if is_running_on_cloud
    include_recipe "::stage-custom-ldif"
end

run_mintpress_project!(_item_code.downcase, my_topology_vars, environment_name, password_vault_name, urls: consoles, release_version: asset_vars['release_version'])
