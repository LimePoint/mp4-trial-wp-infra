require 'tempfile'
require 'base64'
require 'net/ssh'
require 'net/sftp'

asset_list = ['obpobh','obpobu','obpsoa','obposb','obpbip','obpodi','obpcid','obpcim','obpoam','obpoid','obpoim','obpipm','obpdoc','obpurm']

if node.run_state['mintpress_action']!='destroy'

	# make our utils usable from Recipe, and from RubyBlock and within Template
	Chef::Recipe.send(:include, OBPOrchestration::Utils)
	Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
	Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

	_item_code = 'OBPDATAEXTRACT'
    asset_code = lookup_catalogitem_property(_item_code,'asset_code')
    schema_list = lookup_catalogitem_property(_item_code,'schema_list').upcase
    target_db = lookup_catalogitem_property(_item_code,'db_svc_name').upcase
     return unless (node.run_state[_item_code] && asset_list.include?(asset_code))
    puts "Got the assetcode #{asset_code} from build properties"
    tmpHash={"asset_code" =>asset_code,"target_db"=>target_db,"schema_list"=>schema_list}
    #pp node.run_state[_item_code.upcase]['properties']

	environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
	environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

	global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
	node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge(node.run_state[_item_code.upcase]['properties']).to_h.dup

	my_topology_vars = topology_vars(_item_code)
    db_version = my_topology_vars['common']['database_version']

	password_vault_name = my_topology_vars['common']['password_vault_name']
    new_stage_location = "/oracle/stage/db_dumps/#{environment_name}/"+Time.now.strftime('%Y-%m-%d')+"/#{asset_code}"
    remote_path = "/tmp/tmp_dpump"

	if node.run_state.key?('mintpress_action')
		action = node.run_state['mintpress_action']
	else
		action = 'uploadonly'
	end

	ssh_keyfile="/home/mintpress/.ssh/id_rsa"

	if action=='provision' or action=='deploy'

        # Step 1: Create a staging directory on the Mintpress box
        file "/tmp/tmp_#{environment_code}_#{asset_code}.json" do
            content tmpHash.to_json
            mode 0755
        end
        bash "creating #{new_stage_location}" do
            code <<-EOSH
            mkdir -p #{new_stage_location}
            chmod -R 755 #{new_stage_location}
            EOSH
        end

        log "Starting Datapump Emport..."
		# Step 2: Extract the data from the DB schema and upload the dumpfiles to the staging area.
		ruby_block "Datapump Export" do
			block do
                db_hostname=my_topology_vars[asset_code]['database']['scan_address']
                if db_version == "12.2.0.1"
                    db_name=my_topology_vars[asset_code]['database']['service_name'].gsub('_','')
                else
                    db_name=my_topology_vars[asset_code]['database']['service_name'].gsub('_','')[0..7]
                end

                Net::SSH.start(db_hostname, "oracle", :keys => [ssh_keyfile], :verify_host_key => Net::SSH::Verifiers::Null.new) do |ssh|
					ssh.sftp.upload!("/tmp/tmp_#{environment_code}_#{asset_code}.json","/tmp/tmp_#{environment_code}_#{asset_code}.json")
					result=ssh.exec!("chef-client -l info -c /home/oracle/chef/client.rb -o obp-environmint-custom::datapump-schema-extract -j '/tmp/tmp_#{environment_code}_#{asset_code}.json'")
					puts "Datapump result was ...\n #{result}"

                    if result.include?("Error executing action")
					  raise "Datapump export finished with errors."
                    else
                      puts "Completed Datapump Export. Uploading the dumpfiles to staging location #{new_stage_location}"
                    end

                    if my_topology_vars['common']['database_version'] != "12.2.0.1"
                        dplog_loc=ssh.exec!("grep "+db_name+" /etc/oratab|awk -F ':' '{print $2}'").rstrip+"/rdbms/log"
                    else
                        dplog_loc=ssh.exec!("grep "+db_name+" /etc/oratab|awk -F ':' '{print $2}'").rstrip+"/../admin/#{db_name}/dpdump"
                    end

                    ssh.sftp.dir.glob("#{remote_path}", "expdp*") do |fname|
                        ssh.sftp.download!("#{remote_path}/"+fname.name,"#{new_stage_location}/"+fname.name)
                    end

                    ssh.sftp.dir.glob("#{dplog_loc}", "expdp*.log") do |fname|
                        ssh.sftp.download!("#{dplog_loc}/"+fname.name,"#{new_stage_location}/"+fname.name)
                    end
                end
			end
		end
		log "Datapump Export Successful."
	end
end
