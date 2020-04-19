require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPOBH'
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

password = PasswordVault.get_password(password_vault_name, 'obpobh', 'keystorepass')
PasswordVault.put_password(password_vault_name, code, 'keystorepass', password)

if is_running_on_cloud
	# Create the password for OBPREADONLY
	p = PasswordVault.get_password(password_vault_name, 'obpobh', 'obpreadonly' )
end

#### End asset specific code      ####

#### Update Oracle Console URLs ####
consoles = [
	{
		"itemCode" => _item_code,
		"name" => "wls_console",
		"description" => "Oracle Weblogic Administration Console",
		"url" => asset_vars['frontend']['protocol'] + '://' + asset_vars['frontend']['admin_host'] + ":" + asset_vars['frontend']['admin_port'] + "/console"
	},
	{
		"itemCode" => _item_code,
		"name" => "em_console",
		"description" => "Oracle Fusion Middleware Control Console",
		"url" => asset_vars['frontend']['protocol'] + '://' + asset_vars['frontend']['admin_host'] + ":" + asset_vars['frontend']['admin_port'] + "/em"
	}
]

run_mintpress_project!(_item_code.downcase, my_topology_vars, environment_name, password_vault_name, urls: consoles, release_version: asset_vars['release_version'])