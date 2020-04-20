if is_running_on_cloud and node.chef_environment != 'wptest'

	Chef::Log.info("------------ I am service catalog custom in the cloud ----------")

    _item_code = node.run_state['current_code']
    environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
    environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

    global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
    node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge!(node.run_state[_item_code.upcase]['properties']).insensitive

    my_topology_vars = topology_vars(_item_code)
    asset_vars = my_topology_vars[_item_code.downcase]
    password_vault_name = my_topology_vars['common']['password_vault_name']

	keystore_pass =  Mint::AesEncryption.decrypt(PasswordVault.get_password(password_vault_name, _item_code.downcase, 'keystorepass'))

	mintpress_property "fixup-ms-listen" do
		asset "global"
		tree "site.environmentList.*.mwTopologyList.*.domainList.*.managedServerList"
		name "listenAddress"
		value "${_.machine.nodemanager.host.basename}.wpdev.mintpress.io"
	end

	mintpress_property "admin-listen" do
		asset "global"
		tree "site.environmentList.*.mwTopologyList.*.domainList.adminServer"
		name "listenAddress"
		value "${_.machine.nodemanager.host.basename}.wpdev.mintpress.io"
	end

	mintpress_property "enable-exalogic-optimizations" do
		asset "global"
		tree "site.environmentList.*.mwTopologyList"
		name "targetPlatform"
		value "x86-64"
	end

	mintpress_property "disable-ext-network-channels" do
		asset "global"
		tree "site.resourceList.*ExtChanne*.attributes"
		name "Enabled"
		value "false"
	end

	mintpress_property "disable-ext-network-channels" do
		asset "global"
		tree "site.resourceList.wgchannel.attributes"
		name "Enabled"
		value "false"
	end

	mintpress_property "disable-fan" do
		asset "global"
		tree "site.resourceList.JDBCSystemResource.params.JDBCResource.params.JDBCOracleParams.attributes"
		name "FanEnabled"
		only_existing true
		force_attribute true
		value "false"
	end

	mintpress_property "disable-ons" do
		asset "global"
		tree "site.resourceList.JDBCSystemResource.params.JDBCResource.params.JDBCOracleParams.attributes"
		name "OnsNodeList"
		only_existing true
		force_attribute true
		value "None"
	end

	mintpress_property "all-in-parallel" do
		asset "global"
		tree "site.environmentList.*.mwTopologyList.*.domainList"
		name "mintpress.startup_parallel"
		value "8"
	end

	mintpress_executeitem "wait-rcu-ui" do
		asset "obpobu"
		server '*'
		perform_when "pre-rcu"
		value "RESULT=1 ; while [ $RESULT != 0 ]; do export ORACLE_HOME=/oracle/stage/sqlplus/client/11.2.0/ ; export LD_LIBRARY_PATH=$ORACLE_HOME/lib ; $ORACLE_HOME/bin/sqlplus OBPHOST_OBP/$(Mint::AesEncryption.decrypt(PasswordVault.get_password('#{node.chef_environment}', 'obpobh', 'OBPHOST' )))@${/databases.host.address}:${/databases.port}/${/databases.serviceName} </dev/null 2>&1 | grep Connected.to ; RESULT=$? ; sleep 5 ; done"
	end

	mintpress_executeitem "check-db" do
		asset "global"
		server '*'
		perform_when "pre-rcu"
		value "RESULT=1 ; while [ $RESULT != 0 ]; do export ORACLE_HOME=/oracle/stage/sqlplus/client/11.2.0/ ; export LD_LIBRARY_PATH=$ORACLE_HOME/lib ; $ORACLE_HOME/bin/sqlplus llama/duck@${/databases.host.address}:${/databases.port}/${/databases.serviceName} </dev/null 2>&1 | grep logon.denied ; RESULT=$? ; sleep 5 ; done"
	end


	mintpress_executeitem "check-db-startup" do
		asset "global"
		server '*'
		perform_when "pre-start"
		value "RESULT=1 ; while [ $RESULT != 0 ]; do export ORACLE_HOME=/oracle/stage/sqlplus/client/11.2.0/ ; export LD_LIBRARY_PATH=$ORACLE_HOME/lib ; $ORACLE_HOME/bin/sqlplus llama/duck@${/databases.host.address}:${/databases.port}/${/databases.serviceName} </dev/null 2>&1 | grep logon.denied ; RESULT=$? ; sleep 5 ; done"
	end

	# Ensure to run XA views on OIM and CIM Dbs
	mintpress_executeitem "xa-databases" do
		asset "obpoim,obpcim"
		value "chef-client -l info -c ~/chef/client.rb -o obp-environmint-custom::create-xaviews"
		perform_when "pre-rcu"
	end

	# Some SSL - force wildcards, jsse
	# FIXME: product defect
	# Do not do for OID/CID 11g but is requirted for OID/CID 21c
	if !(node.run_state['OBPOID'] && global_properties['obpoid']['release_version'] != '1.7.0') and !(node.run_state['OBPCID'] && global_properties['obpcid']['release_version'] != '1.7.0')
		mintpress_ssl_config 'mintpress.io ssl setup' do
			asset "global"
			keystorename "wpdev.jks"
			keyid "wpdev"
			truststorename "wpdev.jks"
            #certpw "literal:/welcome1"
			certpw "literal:/#{keystore_pass}"
			certpath "${/domains.locationPath}/certs"
			certsource "/oracle/stage/certs/wc"
			wildcard true
			force_jsse true
		end
	end

	mintpress_startup_parameter "posixmuxer" do
		asset "global"
		server "*"
		parameters ["-Dweblogic.MuxerClass=weblogic.socket.PosixSocketMuxer"]
		matches ["-Dweblogic.MuxerClass=weblogic.socket.PosixSocketMuxer"]

	end

	mintpress_internal_variable "autoBaseline" do
		variable "autoBaseline"
		asset "global"
		value "true"
	end

end

# this is applicable for both onprem and ocloud
mintpress_property "startup-managed-servers-in-parallel" do
	asset "global"
	tree "site.environmentList.*.mwTopologyList.*.domainList"
	name "mintpress.startup_parallel"
	value "10"
end

mintpress_property "startup-managed-servers-order" do
	asset "obpipm"
	tree "site.environmentList.*.mwTopologyList.*.domainList"
	name "mintpress.cluster_startup_order"
	value "*ucm*,*ipm*"
end

mintpress_property "startup-managed-servers-order" do
	asset "obpoim"
	tree "site.environmentList.*.mwTopologyList.*.domainList"
	name "mintpress.cluster_startup_order"
	value "*soa*,*oim*"
end

mintpress_property "startup-managed-servers-order" do
	asset "obpcim"
	tree "site.environmentList.*.mwTopologyList.*.domainList"
	name "mintpress.cluster_startup_order"
	value "*soa*,*oim*"
end

# Restart only SOA, OSB and IPM domains after a Rebuild or Provision.
['stopManagedBefore','stopAdminBefore','startAdminAfter','startManagedAfter'].each do |s|
    mintpress_property "add_restart_attr_#{s}" do
        tree "site.environmentList.*.mwTopologyList.*.executeList.FMW-Domain-Restart"
        name s
        value "true"
        only_if {['provision','rebuild'].include?node.run_state['mintpress_action'] and (node.run_state['OBPSOA'] or node.run_state['OBPOSB'] or node.run_state['OBPIPM'])}
    end
end
