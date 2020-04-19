require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

usr = JSON.parse(::File.read("#{__dir__}/../files/asset_usr_list.json"))
vault_name = node.chef_environment

usr.each do |asset_code,uid|
  case
  when asset_code.match('all')
    PasswordVault.put_password(vault_name, 'all', 'truststorepass', 'welcome1')
  else
    if uid.is_a?(Array)
      uid.each do |u|
        case
        when u.match('storepass')
          password = safe_get_password(vault_name, 'all', 'truststorepass')
          PasswordVault.put_password(vault_name, asset_code, u, password)
        when u.match('SYS')
          password = safe_get_password(vault_name, 'database', 'dbsyspassword')
          PasswordVault.put_password(vault_name, asset_code, u, password)
        when u.match('ODI')
          PasswordVault.get_password(vault_name, asset_code, u, minimum_password_length: 10, include_symbol: false )
        else
          PasswordVault.get_password(vault_name, asset_code, u)
        end
      end
    end
  end
end
