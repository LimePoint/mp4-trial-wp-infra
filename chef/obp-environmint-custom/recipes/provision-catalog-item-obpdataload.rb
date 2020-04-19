require 'tempfile'
require 'base64'

if node.run_state['mintpress_action']!='destroy'

	# make our utils usable from Recipe, and from RubyBlock and within Template
	Chef::Recipe.send(:include, OBPOrchestration::Utils)
	Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
	Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

	_item_code='OBPDATALOAD'
    return unless node.run_state[_item_code]

	environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
	environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')
    asset_code = 'obpobh'
    errmsg = ["Compile Error","Error executing action","Linux-x86_64 Error",
              "ORA-27041:","ORA-30036:","ORA-31640:","ORA-39000:","ORA-39001:",
              "ORA-39002:","ORA-39059:","ORA-39140:","ORA-39171:"]

	global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
	node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge!(node.run_state[_item_code.upcase]['properties']).insensitive

	my_topology_vars = topology_vars(_item_code)

	pc=lookup_catalogitem_providerCode(_item_code)
    dpdump_loc=lookup_catalogitem_property(_item_code,'dumpfile_path').chomp("/")
	override_flg=lookup_catalogitem_property(_item_code,'oidp').upcase
    forcekill=lookup_catalogitem_property(_item_code,'force').upcase

    if override_flg == 'TRUE'
        raise "INVALID PATH!!. Must be a 'gold_copy' PATH" if !dpdump_loc.include?("/gold_copy")
    else
        dpdump_loc = my_topology_vars['common']['dataload_path'].chomp("/")
    end
    tmpHash={"dpdump_loc" => dpdump_loc, "forcekill" => forcekill}

	password_vault_name = my_topology_vars['common']['password_vault_name']
	obh_hostname=my_topology_vars[asset_code]["hostnameList"][0] + my_topology_vars[asset_code]["dns_domain_name"]

	if node.run_state.key?('mintpress_action')
		action = node.run_state['mintpress_action']
	else
		action = 'uploadonly'
	end

	ssh_keyfile="/home/mintpress/.ssh/id_rsa"

	if action=='provision' or action=='refresh'
		assets_to_action = ["#{environment_code}_OBPOBH", "#{environment_code}_OBPOBU", "#{environment_code}_OBPOSB", "#{environment_code}_OBPBIP", "#{environment_code}_OBPODI", "#{environment_code}_OBPSOA"]
        if lookup_catalogitem_property(_item_code,'shut_depfmw').upcase == 'TRUE'
            log "Stopping assets #{assets_to_action}"
		# Step 1: stop all assets that connect to the OBP DB schema
		    mintpress_catalog_action "execute-command-#{action}" do
			    asset_list assets_to_action
			    action_to_perform 'shutdownmanaged'
			    provider_code pc
			    prefer_code true
			    ignore_console_state true
			    request_delay 1
			    max_parallel 20
			    launch_missing true
			    ignore_failure true
			    always_run true
			    retry_count 2
			    console_url node['environmint']['designtime']['server_url']
			    console_username node['environmint']['designtime']['username']
			    console_password PasswordVault.get_password('mintpress', 'designtime', node['environmint']['designtime']['username'])
		    end
		    log "Assets #{assets_to_action} Stopped Successfully."
        end

		log "Starting Data Import..."
		# Step 2: reload the database
        file "/tmp/tmp_#{environment_code}_#{_item_code}.json" do
            content tmpHash.to_json
            mode 0755
        end
        ruby_block "Data Import" do
            block do
                Net::SSH.start(obh_hostname, "oracle", :keys => [ssh_keyfile], :verify_host_key => Net::SSH::Verifiers::Null.new) do |ssh|
                    ssh.sftp.upload!("/tmp/tmp_#{environment_code}_#{_item_code}.json","/tmp/tmp_#{environment_code}_#{_item_code}.json")
                    result=ssh.exec!("chef-client -l info -c /home/oracle/chef/client.rb -o obp-environmint-custom::obpobh-load-rcu-data -j '/tmp/tmp_#{environment_code}_#{_item_code}.json'")
                    puts "Datapump result was ...\n #{result}"
                    if result.scan(Regexp.union(errmsg)).size > 0
                        raise "Dataload resulted in failure :("
                    end
                end
            end
        end

		log "Data Import Successful."

		# Step 3: re-run obp vars
		log "Overriding Database values; Running obp-override-environment-variables on host #{obh_hostname}"
		ruby_block "Override OBP environment variables" do
			block do
				Net::SSH.start(obh_hostname, "oracle", :keys => [ssh_keyfile], :verify_host_key => Net::SSH::Verifiers::Null.new) do |ssh|
					puts "chef-client -l info -c /home/oracle/chef/client.rb -o obp-environmint-custom::obp-override-environment-variables"
					result=ssh.exec!("chef-client -l info -c /home/oracle/chef/client.rb -o obp-environmint-custom::obp-override-environment-variables")
					puts "RESULT: #{result}"
					#if result.include?("ERROR")
					#  raise "Variables update resulted in failure :("
					#end
				end
			end
		end
		log "Override Database values successful."

        if lookup_catalogitem_property(_item_code,'startup_depfmw').upcase == 'TRUE'
            log "Starting assets #{assets_to_action}"
		# Step 4: restart all middleware.... boo
		    mintpress_catalog_action "execute-command-#{action}" do
			    asset_list assets_to_action
			# RB: not required anymore
			#depends Hash({ "#{environment_code}_OBPOBU" => "#{environment_code}_OBPOBH" })
			    action_to_perform 'startupmiddleware'
			    provider_code pc
			    prefer_code true
			    ignore_console_state true
			    request_delay 1
			    max_parallel 20
			    launch_missing true
			    always_run true
			    retry_count 2
			    console_url node['environmint']['designtime']['server_url']
			    console_username node['environmint']['designtime']['username']
			    console_password PasswordVault.get_password('mintpress', 'designtime', node['environmint']['designtime']['username'])
		    end
		    log "Assets #{assets_to_action} started Successfully."
        end
	end
end
