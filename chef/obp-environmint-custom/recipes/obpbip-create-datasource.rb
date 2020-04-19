# Author: Harsha Gurram

# This recipe creates OBPReportsDataSource in BI Publisher console. Can be extended if new datasources are required.
# This can be run over and over again.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

log "Verify And Create DataSource Entries if do not exist"


bash 'Verifying And Creating DataSource Entries' do
  code <<-EOH
    export OBPREPORTSDS="   <dataSource name=\\"obpReportsDataSource\\">\\n      <connection>\\n         <connectionType>jndi</connectionType>\\n         <proxyAuthentication>false</proxyAuthentication>\\n         <jndiName>jdbc/FCBDataSource</jndiName>\\n      </connection>\\n      <acl>\\n         <policy>\\n            <subject>\\n               <rolename>BIConsumer</rolename>\\n            </subject>\\n            <action name=\\"read\\"/>\\n         </policy>\\n      </acl>\\n   </dataSource>\\n</dataSources>"
	if grep obpReportsDataSource /oracle/app/runtime/obpbip/bidata/components/bipublisher/repository/Admin/DataSource/datasources.xml; then
		echo 'obpReportsDataSource exists'
	else
		sed -i "s#</dataSources>#\$OBPREPORTSDS#g" /oracle/app/runtime/obpbip/bidata/components/bipublisher/repository/Admin/DataSource/datasources.xml
	fi
    EOH
end