require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

node.run_state.merge!(node)

environment_code = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase.strip.tr('.', '').tr('_', '').tr(' ', '')

dataBag = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = dataBag['common']['password_vault_name']


# Generate LDIF for Nam Users
# Process files and drop them to /oracle/stage
template 'nam-users.ldif' do
	source "ldif/nam_users/nam-users.ldif.erb"
	path "/oracle/stage/custom/westpac/#{environment_code}_nam-users.ldif"
	variables(
		:NamEnvName => dataBag['common_properties']['NamEnvName'],
		:NamUsrPwd => Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/ldap/NamUsrPwd").value)
	)
	mode '0777'
end

# Generate ldif for content
template 'nam-users-group-mapping.ldif' do
	source "ldif/nam_users/nam-users-group-mapping.ldif.erb"
	path "/oracle/stage/custom/westpac/#{environment_code}_nam-users-group-mapping.ldif"
	variables(
		:NamEnvName => dataBag['common_properties']['NamEnvName']
	)
	mode '0777'
end
