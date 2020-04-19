# Author: Harsha Gurram
# Recipe to retarget jms resources of host domain
require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

# Recipe to provide JMS Queue Access

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"


bash 'Executing jms_retarget.py' do
  code <<-EOH
    echo aW1wb3J0IHN5cwoKdHJ5OgogICAgY29ubmVjdChzeXMuYXJndlsxXSxzeXMuYXJndlsyXSxzeXMuYXJndlszXSkKICAgIGVkaXQoKQogICAgc3RhcnRFZGl0KCkKICAgIGptc1NlcnZlciA9IGdldE1CZWFuKCcvSk1TU2VydmVycy9vYnBob3N0X3NlcnZlcjFqbXNzZXJ2ZXInKQogICAgcHJpbnQgam1zU2VydmVyCiAgICBzZXJ2ZXI9Z2V0TUJlYW4oJy9TZXJ2ZXJzL29icGhvc3Rfc2VydmVyMScpCiAgICBwcmludCBzZXJ2ZXIKICAgIGptc1NlcnZlci5zZXRUYXJnZXRzKFtzZXJ2ZXJdKQogICAgcHMgPSBnZXRNQmVhbignL0pEQkNTdG9yZXMvb2JwaG9zdF9zZXJ2ZXIxSkRCQ1N0b3JlJykKICAgIHBzLnNldFRhcmdldHMoW3NlcnZlcl0pCiAgICBzYXZlKCkKICAgIGFjdGl2YXRlKCkKICAgIGRpc2Nvbm5lY3QoKQpleGNlcHQ6CiAgICBkdW1wU3RhY2soKQogICAgcHJpbnQgJ0VSUk9SOiBGYWlsZWQgaW4gcmV0YXJnZXR0aW5nIGptcyB0YXJnZXRzJwogICAgdW5kbyhkZWZhdWx0QW5zd2VyPSd5JykKICAgIHN5cy5leGl0KDEpCg== | base64 -d > /tmp/jms_retarget.py;/oracle/app/binaries/obpobh/fmw/oracle_common/common/bin/wlst.sh /tmp/jms_retarget.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
end