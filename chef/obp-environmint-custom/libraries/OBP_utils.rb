require_relative 'deputils'
require 'json'

module PasswordVault
  class <<self
    # THis duplicates the reset_cache function that exists later...
    def reset_cache
      @@bagcache_item=nil
      @@bagcache_valid=false
      @@bagcache_vault=nil
      @@bagcache=nil
      @@pwcache = {}
    end
  end
end

module OBPOrchestration
    module Utils
        include Chef::DSL::IncludeRecipe

    def safe_get_password(a,b,c)
        pw=nil
        tries = 0
        # fall out of it's destroy, since the vault may just be wrecked anyhowe....
        if node.run_state['mintpress_action']=='destroy'
            return PasswordVault.get_password(a,b,c)
        end
        while pw.nil?
            Chef::Log.info("Getting PW from #{a}/#{b}/#{c}")
            pw=PasswordVault.get_password(a,b,c,autocreate: false)
            Chef::Log.info("Attempting to clear cache") if pw.nil?
            PasswordVault.reset_cache if pw.nil?
            rand(60) if pw.nil?
        end
        return pw
    end

    def get_all_clusters(parent, myHash)
        response = Hash.new
        myHash.each {|key, value|
        if value.is_a?(Hash)
            response = response.merge(get_all_clusters(key, value))
        else
            if key=='cluster_name'
                response = response.merge({parent => value})
            end
        end
        }
        response
    end

		def run_mintpress_project!(item_code, topology_vars, env_name, password_vault_name, urls: nil, release_version: nil, deps: nil, steps: nil, force_upload: nil, build_machines: false, generate_certs: false, machine_ram: 32, machine_cpu: 8)

			# If we are on cloud, build deps from util
			# RB TODO: This should also work on on-prem
			if is_running_on_cloud
				build_deps(topology_vars)
			end

			if deps.nil?
				deps=get_standard_deps(node.run_state['mintpress_action'])
			end

			if steps.nil?
				steps=get_standard_steps(node.run_state['mintpress_action'])
			end

			if node.run_state['mintpress_action']=='patch'
				steps=['Binaries']
			end

			if force_upload.nil?
				force_upload = get_standard_force_upload(node.run_state['mintpress_action'])
			end

			asset_vars = topology_vars[item_code.downcase]

			##### -- Store password in the vault -- #####
			if asset_vars.key?('wls_admin_user') and asset_vars.key?('wls_admin_password')
				PasswordVault.put_password(password_vault_name, item_code, asset_vars['wls_admin_user'], asset_vars['wls_admin_password'])
			end

			## Read scale out properties
			mservers_per_host = {}
			number_of_hosts = {}
			mservers_per_host['*'] = asset_vars['managed_servers_per_host'].to_i
			number_of_hosts['*'] = asset_vars['hostnameList'].length*asset_vars['managed_servers_per_host'].to_i

			my_host_list = {}
			my_base_host_list = {}
			my_host_list['*'] = asset_vars['hostnameList']
			my_base_host_list['*'] = asset_vars['hostnameList']
			asset_vars.each do |s, v|
				if v.is_a?(Hash) and v['hostnameList']
					my_host_list["#{s}*"]=v['hostnameList']
					if v['managed_servers_per_host']
						number_of_hosts["#{s}*"]=v['hostnameList'].length*v['managed_servers_per_host'].to_i
					else
						number_of_hosts["#{s}*"]=v['hostnameList'].length*asset_vars['managed_servers_per_host'].to_i
					end
					# would not normally use this...
					if v['baseHostnameList']
						my_base_host_list["#{s}*"]=v['baseHostnameList']
					else
						my_base_host_list["#{s}*"]=v['hostnameList']
					end
				end
			end

			# if we are on cloud, create the machines and the certs
			if is_running_on_cloud
				build_machines=true
				generate_certs = true

				# Do not build the machines if the action is not provision and if the asset is OBPIDM since it is shared on OID
				if node.run_state['mintpress_action']=='uploadonly' or (node.run_state['mintpress_action']!='provision' and item_code.upcase=='OBPIDM')
					build_machines=false
				end

				# if provisioning, always force upload, this will only be true on cloud hence in this if condition
				if force_upload.nil?
					force_upload = get_standard_force_upload(node.run_state['mintpress_action'])
					if node.run_state['mintpress_action']=='provision'
						force_upload=true
					end
				end

				# If building machines, decide what to build.
				if build_machines
                    # Set what we want to build. The VMs are all pretty standard, DB types are VM.Standard.E2.8 and non-dbs are VM.Standard.E2.4
                    # These defaults are set in oci_libs under oci-common cookbook. I am only overriding what I need.
					standard_run_list=['recipe[oci-cloud::default]']
					providerCode = lookup_catalogitem_providerCode(item_code)
					asset_vars['hostnameList'].each do |h|
                      host_opts = {}
                      host_opts[:hostname] = "#{h}.wpdev.mintpress.io"
                      host_opts[:environment_name] = env_name
                      host_opts[:instance_type] = 'VM.Standard.E2.4'
                      host_opts[:operating_system] = 'Oracle Linux'
                      host_opts[:operating_system_version] = 7
                      host_opts[:disk_size] = 50
                      host_opts[:run_list] = ['oci-bootstrap::default']
                      attrs = {
                          "environmint": { "orchestration_key": "#{node.run_state['orchestration_metadata']['uuid']}" },
                          "provisioning_env": "environmint-provisioning",
                          "provider_id": providerCode
                      }
                      host_opts[:node_attributes] = attrs
                      host_opts[:create_cnames] = true
                      host_opts[:create_friendly_names] = true
                      # Transform hash keys to symbols; no specific reason just personal preference
                      host_opts.transform_keys!(&:to_sym)
                      oci_host = MintOCIHost.new(host_opts)
                      if node.run_state['mintpress_action']=='provision'
                        Chef::Log.info("Provision action detected. Creating the VM")
                        oci_host.create
                      elsif node.run_state['mintpress_action']=='destroy'
                        Chef::Log.info("Destroy action detected. Deleting the VM")
                        oci_host.destroy
                      else
                        # Do nothing
                      end
                    end
				end

				# We use wildcard certificates on ocloud issues by LimePoint
				if generate_certs
					# since all of the templates use 0..-2 notation, here too  we shall.  except that wallets do not....
					basehost=asset_vars['hostnameList'][0][0...-2]

                    # The keystore/truststore pass is hardcoded because it is a big change right now
                    # no easy way to do this right now. It needs a bit of refactoring
                    # CHANGEME - This needs to be changed everytime the password is changed
                    keystore_pass = 'EodVD6DRv_SZ7SfNjc31'
					PasswordVault.put_password(password_vault_name, item_code.downcase, 'keystorepass', keystore_pass)

                    truststore_pass = 'EodVD6DRv_SZ7SfNjc31'
					PasswordVault.put_password(password_vault_name, item_code.downcase, 'truststorepass', truststore_pass)

                    # The base of all certs, common certs like trust and cacerts, adapters etc are picked from this location
                    # This also serves as a base for creating env specific certs.
                    base_cert_path = "/oracle/stage/certs/gen2_certs"
                    env_cert_path = "#{base_cert_path}/#{env_name}"

                    Chef::Log.info "Setting base_cert_path to [#{base_cert_path}]"
                    Chef::Log.info "Setting env_cert_path to [#{env_cert_path}]"

                    # Make appropriate environments
                    raise "Could not create environment directory [#{env_cert_path}] for certificate" unless system("mkdir -p #{env_cert_path}")
                    raise "Could not copy cwallet.sso" unless system("cp -u #{base_cert_path}/wpdev_wallet/cwallet.sso #{env_cert_path}/#{basehost}01_wallet")
                    raise "Could not copy wpdev_keystore.jks as #{env_cert_path}/#{basehost}.jks" unless system("cp -u #{base_cert_path}/wpdev_keystore.jks #{env_cert_path}/#{basehost}.jks")
                    raise "Could not copy wpdev_keystore.jks as #{env_cert_path}/wpdev_trust.jks" unless system("cp -u #{base_cert_path}/wpdev_keystore.jks #{env_cert_path}/wpdev_trust.jks")
                    raise "Could not copy root.crt" unless system("cp -u #{base_cert_path}/root.crt #{env_cert_path}/cacerts.pem")
                    raise "Could not copy adapters.jks" unless system("cp -u #{base_cert_path}/adapters.jks #{env_cert_path}/adapters.jks")
                    raise "Could not copy cacerts" unless system("cp -u #{base_cert_path}/cacerts #{env_cert_path}/cacerts")
				end
			end

			## Make sure the ruby upload always run
			log "delay" do
				notifies :run, 'ruby_block[upload_files]', :delayed
			end

			####  -- Define Minpress project --

            # redirect traffic to localhost instead of the F5 to avoid timeouts!
            if topology_vars['runtime']['url']=='https://mintpress-rtd-csh.srv.westpac.com.au/cshtest'
              topology_vars['runtime']['url']='https://localhost:17002/cshtest'
            elsif topology_vars['runtime']['url']=='https://mintpress-rtp-csh.srv.westpac.com.au/csh'
              topology_vars['runtime']['url']='https://localhost:17002/csh'
            end

            mintpress_project item_code do
                
                designtime_url node['environmint']['designtime']['server_url']
                designtime_username node['environmint']['designtime']['username']
                designtime_password PasswordVault.get_password('mintpress', 'designtime', node['environmint']['designtime']['username'])
                
                if  asset_vars['register_with_drift'] == 'true'
                    drift_url node['environmint']['drift']['server_url']
                    drift_username node['environmint']['drift']['username']
                    drift_password PasswordVault.get_password('mintpress', 'drift', node['environmint']['drift']['username'])
                end

				# Dont complain if you can't shutdown
				if node.run_state['mintpress_action'].include?('shutdown')
					nonfatal []
				end

				## Define list of hosts for domain
				scaleup_host_list Hash({item_code.downcase => my_host_list})
				scaleup_base_host_list Hash({item_code.downcase => my_base_host_list})

				# Configure total number of managed serves
				scaleup_cluster_nodes Hash({item_code.downcase => number_of_hosts})

				## Configure scaleout option per host
				scaleup_nodes_per_host Hash({item_code.downcase => mservers_per_host})

				port_increment true

				force_upload force_upload
				if steps!=nil
					steps steps
				end
				if deps!=nil
					dependency_map deps
				end
				topology_variables lazy { topology_vars }
				if release_version!=nil
					templates "assets/" + item_code.downcase + "-" + release_version + ".json"
				else
					templates "assets/" + item_code.downcase + ".json"
				end

				# Reducing the retry count to speed up rebuilds
				retrycount 2

				always_run ['Startup', 'Startup Admin', 'Shutdown', 'Startup Parallel', 'Shutdown Managed']

				action :nothing
			end

			unless urls.nil?
				update_console_urls_for_catalogitem(node['environmint']['orchestration']['key'], item_code, urls)
			end

			ruby_block "upload_files" do
				block do
					if topology_vars['common']['git_commit_on_upload'].downcase == 'true'

						%x[ mkdir -p "#{topology_vars['common']['git_repo_path']}/json-files/uploaded/#{env_name.downcase}" ]
						if ::File.exist?("/tmp/#{env_name}_#{item_code.upcase}_#{item_code.downcase}-#{release_version}.json") or ::File.exist?("/tmp/#{env_name}_#{item_code.upcase}_#{item_code.downcase}.json")
							if release_version!=nil
								::FileUtils.cp "/tmp/#{env_name}_#{item_code.upcase}_#{item_code.downcase}-#{release_version}.json", "#{topology_vars['common']['git_repo_path']
								}/json-files/uploaded/#{env_name.downcase}/#{env_name}_#{item_code.downcase}.json", :verbose => true
							else
								::FileUtils.cp "/tmp/#{env_name}_#{item_code.upcase}_#{item_code.downcase}.json", "#{topology_vars['common']['git_repo_path']
								}/json-files/uploaded/#{env_name.downcase}/#{env_name}_#{item_code.downcase}.json", :verbose => true
							end

							# remove the file in /tmp
							::FileUtils.rm_f "/tmp/#{env_name}_#{item_code.upcase}_#{item_code.downcase}.json"
							## Add files to Git
							puts 'Adding generated JSON files to Git'
							%x[ cd #{topology_vars['common']['git_repo_path']} && git add "json-files/uploaded/#{env_name.downcase}" && git commit json-files -m "Updated generated JSON files for #{env_name.upcase} #{item_code.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
						end
					end
				end
				action :nothing
			end


			ruby_block "upload_audit_log" do
				block do
					puts "------------ Upload Audit Log ----------"

					if topology_vars['common']['git_commit_on_upload'].downcase == 'true'
						puts "Create Folder for Audit Log "
						%x[ mkdir -p "/tmp/json-files/uploaded/#{env_name.downcase}/audit_data" ]
						environment_name = env_name.downcase
						asset_name = item_code.downcase
						mintpress_action = node.run_state['mintpress_action']
						action_start_time = Time.now.strftime("%F %T")
						action_end_time =	Time.now.strftime("%F %T")
						related_build_number =	"NA"
						cookbook_name = run_context.cookbook_collection[cookbook_name].name
						cookbook_version = run_context.cookbook_collection[cookbook_name].version
						project_url ="NA"
						status = true

						env_audit_file = "/tmp/json-files/uploaded/#{env_name.downcase}/audit_data/#{env_name.downcase}_audit_file.json"
						if ::File.exist?(env_audit_file)
							puts "Let's open the file and merge the content"
							audit_log = JSON.parse(::File.read(env_audit_file))
						else
							puts "It is a new environment or no previous audit file exists, lets handle this "
							puts "create a new hash"
							audit_log = Hash[ "#{environment_name}" => {} ]
						end
						#construct hash here and merge in right branch
						current_audit_data = Hash[  {mintpress_action => {"mintpress_action" => mintpress_action, "action_start_time" => action_start_time, "action_end_time" => action_end_time, "status" => status , "related_build_number" => related_build_number ,"cookbook_name" => cookbook_name,  "cookbook_version" => cookbook_version, "project_url" => project_url} }]
						puts "Current Action Audit Data  #{JSON.pretty_generate(current_audit_data)}"
						if audit_log[environment_name][asset_name]!= nil
							puts "The Asset Code already exists in the audit data, lets merge into that "
							audit_log[environment_name][asset_name].merge!current_audit_data
							puts "Asset Block Merge   #{JSON.pretty_generate(audit_log)}"
						else
							asset_block = Hash[  "#{asset_name}" => {}  ]
							puts "The Asset Code does not exists in the audit data, merge it first"
							audit_log[environment_name].merge!asset_block
							puts "Asset Block Merge before init  #{JSON.pretty_generate(audit_log)}"

							puts "Merge audit data after the asset block initialization"
							audit_log[environment_name][asset_name].merge!current_audit_data
							puts "Asset Block Merge after init   #{JSON.pretty_generate(audit_log)}"

						end
						File.open("#{env_audit_file}","w") do | f |
							f.write(JSON.pretty_generate(audit_log))
						end

					end
				end
				action :nothing
			end
		end
	end
end
