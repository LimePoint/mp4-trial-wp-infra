require 'net/smtp'
require 'tempfile'

# wait for the listen port of one service to be available
def wait_for_server_complete(my_item, child_item, server_name, stage, vars)
	mintpress_executeitem "check-#{my_item}-#{child_item}-#{server_name}-#{stage}" do
		asset "#{my_item}"
		server 'AdminServer'
		perform_when "pre-#{stage}"
		value "LOOP=1 ; while [ $LOOP != 0 ]; do timeout 1 bash -c 'cat < /dev/null > /dev/tcp/#{vars[child_item][server_name]['listen_address']}#{vars[child_item]['dns_domain_name']}/#{vars[child_item][server_name]['listen_port'].to_s}' ; LOOP=$? ; echo 'contacting #{vars[child_item][server_name]['listen_address']}#{vars[child_item]['dns_domain_name']}/#{vars[child_item][server_name]['listen_port'].to_s}' ; sleep 1 ;  done"
	end
end

# wait for all listen ports of a service to be available
def wait_for_asset_complete(my_item, child_item, stage, vars)
	vars[child_item.downcase].each do |k, v|
		if v.is_a?(Hash) and v['listen_address'] and k!='frontend'
			wait_for_server_complete(my_item, child_item, k, stage, vars)
		end
	end
end

def wait_for_databases()
	['online', 'start'].each do |stage|
		mintpress_executeitem "ensure-db-working-#{stage}" do
			asset "global"
			server 'AdminServer'
			perform_when "pre-#{stage}"
			value "export ORACLE_HOME=/oracle/stage/sqlplus/client/11.2.0/ ; export LD_LIBRARY_PATH=$ORACLE_HOME/lib ; export PATH=$PATH:$ORACLE_HOME/bin ; $(out='' ; dbs=getkey(fulldata, 'site.resourceList.JDBCSystemResource.params.JDBCResource.params.JDBCDriverParams') ; if dbs.is_a?(Hash) then dbs=[dbs] end ; dbs.each { |d| if d['properties'] and d['properties']['user'] and d['attributes'] and d['attributes']['Password'] and d['attributes']['Url'] then out+=\"RESULT=1 ; while [ $RESULT != 0 ]; do sqlplus '\"+d['properties']['user']+\"/\"+Mint::AesEncryption.decrypt(resolveInternalFull(d['attributes']['Password'], fulldata))+d['attributes']['Url'].gsub('jdbc:oracle:thin:','') +\"' </dev/null 2>&1 | grep 'Connected.to' ; RESULT=$? ; if [ $RESULT != 0 ]; then sleep 5 ; fi ; done ; \" end } ; out+=\" /bin/true\")"
		end
	end
end

def wait_for_authenticators()
	['online', 'start'].each do |stage|
		mintpress_executeitem "ensure-oid-working-#{stage}" do
			asset "global"
			server 'AdminServer'
			perform_when "pre-online"
			value "$(out='' ; auths=getkey(fulldata, 'site.resourceList.AuthenticationProvider.attributes') ; if auths.nil? then auths=[] ; end ; if !auths.is_a?(Array) then auths=[auths]; end ; auths.each { |d| if d['Host'] and d['Port'] then out+=\"LOOP=1 ; while [ $LOOP != 0 ]; do timeout 1 bash -c 'cat < /dev/null > /dev/tcp/\"+d['Host']+\"/\"+d['Port'].to_s+\"' ; LOOP=$? ; echo 'contacting \"+d['Host']+d['Port'].to_s+\"' ; sleep 1 ;  done ; \" end } ; out+=\" /bin/true\")"
		end
	end
end

# This function will return true if evaluated on ocloud
def is_running_on_cloud()
	if node['dns'] and node['dns']['zone']=='wpdev.mintpress.io'
		return true
	else
		return false
	end
end


# Utility method for email notification
#RB TODO: Make this optional params
def sendEmail(env, from, to, msg, notify_others:0)
	Chef::Log.info("Invoke Send Email now")
	begin

        if notify_others > 0
            message = "#{msg}\n"
        else
            message = "From: MintPress DevOps <#{from}>\n"
            message << "To: recipient_address <#{to}>\n"
            message << "Subject: Deployment  Status for #{env.upcase}\n"
            message << "Date: #{Time.now}\n\n"
            message << "#{env.upcase}  - Deployment  Status\n"
            message << "#{msg}\n"
        end

		if is_running_on_cloud
			
			# If running on cloud, use the wpocloud ID, This is a proper gmail account under LP
			# If you need more details on this account, talk to RB
			
			# Name of the domain
			domain = 'ocloud-mintpress.mintpress.io'
			
			# Name of the GMail user
			gmail_username = 'wpocloud@limepoint.com'
			
			# Get Password from Vault
			gmail_password = Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', 'smtp', 'wpocloud'))
			smtp = Net::SMTP.new 'smtp.gmail.com', 587
			smtp.enable_starttls
			
			smtp.start(domain,gmail_username, gmail_password, :login) do
				smtp.send_message message, from, to
			end
		else
			Net::SMTP.start('appsmtp.thewestpacgroup.com.au', 25) do |smtp|
				smtp.send_message message, from, to
			end
		end
		puts " Email - Sent"
	rescue Exception => e
		Chef::Log.info("Sending email failed, but rescued as it is not a critical to break deployment")
		Chef::Log.info("Error Message: #{e.message}")
		Chef::Log.info("Stack Trace: #{e.backtrace.inspect}")
	end
end

#Utility method to create deployment prop
def createDeploymenProps(env, template_source, vars, artifactory_version)
	Chef::Log.info("Invoke deployment property creation method..")
	Chef::Log.info("Get source template from #{template_source}")
	begin
		
		final_folder="/environmint/tmp/deployment-prop/#{env}"
		unless File.directory?(final_folder)
			FileUtils.mkdir_p(final_folder)
		end
		::Dir.glob("#{__dir__}/../templates/#{template_source}/*.erb").each do |f|
			bn=::File.basename(f)
			template "#{final_folder}/#{bn.gsub('.erb', '')}" do
				source "#{template_source}/#{bn}"
				variables vars
			
			end.run_action(:create)
		end
		uploadDeployProp2Git(env, final_folder, vars)
	
	rescue Exception
		Chef::Log.error("Fatal error while creating deployment properties #{template_source}")
		raise
	end
end

def uploadDeployProp2Git(environment_name, tmp_folder, my_topology_vars)
	Chef::Log.info("Invoke uplaod to git from :  #{tmp_folder} to: #{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/deploy-props ")
	ruby_block "upload deploy prop files to git " do
		block do
			if my_topology_vars['common']['git_commit_on_upload'].downcase == 'true'
				
				%x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/deploy-props" ]
				::FileUtils.cp_r "#{tmp_folder}/.", "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/deploy-props", :verbose => true
				# remove the file in /environmint/tmp
				#::FileUtils.rm_f "tmp_folder"
				## Add files to Git
				puts 'Adding deployment prop files to Git'
				%x[ cd #{my_topology_vars['common']['git_repo_path']} && git add "json-files/uploaded/#{environment_name.downcase}/deploy-props" && git commit json-files -m "Updated generated deployment property files for #{environment_name.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
			end
		end
	end
end

def zipAndPackageArtifactory(environment_name, tmp_folder, my_topology_vars, artifactory_version, artifact)
    Chef::Log.info("Invoke zipAndPackageArtifactory")
    Chef::Log.info("#{self.class.to_s} - #{__method__.to_s} Invoke Zip and Push Artifactory Method Target Folder :  #{tmp_folder} ")
    zip_file_name="#{environment_name}-mint-deploy-properties.zip"
    Chef::Log.info("Here is the Zip File name : #{zip_file_name} ")
    ruby_block "test" do
        block do
            puts "Executing the cmd shell =======>"
            %x[ cd #{tmp_folder} && zip -y -r #{zip_file_name} #{environment_name} ]
            #Lets error out & fail here if zip file is not created
            if(File.exist?("#{tmp_folder}/#{zip_file_name}"))
                Chef::Log.info("Zip File exists - created by  cmd shell ")
            else
                Chef::Log.error("Deploy Props for this env does not exists, Possible failure while creating  Zip File through cmd shell ")
                exit(1)
            end
            # Now Push the File to Artifactory
            path_var = my_topology_vars['common']['deployment']['ARTIFACTORY_URL']
            puts "Path var  #{path_var}"
            artifactory_path = "#{path_var}/au/com/westpac/csh/#{artifactory_version}/mint-deploy-properties/CSH-#{artifactory_version}/#{zip_file_name} "
            Chef::Log.info("#{self.class.to_s}# - #{__method__.to_s} Here is the Artifactory Path in Full #{artifactory_path}")


            # Fix me later by using a Rest Client API , to deal with the error properly - TBD creds from Vault
            %x[cd #{tmp_folder}  && curl --progress --insecure -u MP-001ArtifactoryRW:288tBzyZJ5b0z27AM3M25IT0B9S8ZJ6dH88mW5pQCY2544e5 -X PUT #{artifactory_path} -T #{zip_file_name} -o #{environment_name}-upload-result.txt]

            # remove the zip  file in /environmint/tmp
            ::FileUtils.rm_f "#{tmp_folder}/#{zip_file_name}"
            Chef::Log.info("File removed  : #{tmp_folder}/#{zip_file_name}")
        end
    end
end

#Utility method Tactical to create response file on successful deployment
def createResponseFile(environment_name, csh_release_version)
	puts "Inside method this is the env #{environment_name}"
	Chef::Log.info("Invoke deployment response file  creation method..")
	Chef::Log.info("Get source template from #{csh_release_version}")
	
	begin
		final_folder="/environmint/tmp/reponse_files"
		unless File.directory?(final_folder)
			FileUtils.mkdir_p(final_folder)
		end
		response_file = "/environmint/tmp/reponse_files/#{environment_name}_mintpress_response.json"
		template 'Response File Template' do
			source "#{csh_release_version}/cicd/env_mintpress_response.erb"
			path response_file
			variables(
				variables(
					
					:environment_name => environment_name
				)
			)
			mode '0644'
		end
			
			#uploadResponseFile2Git(environment_name, response_file)
	rescue Exception
		Chef::Log.error("Fatal error while creating deployment Response File for Env:  #{environment_name}")
		raise
	end
end

#Update the response file to GIT , this wil inturn kick off a smoke test automatically
def uploadResponseFile2Git(environment_name, response_file)
	#Hard Code this for now -  it is tactical, need to move this to a variable
	manifest_git_repo_path = "/environmint/gitrepos/buildmanifest"
	Chef::Log.info("Invoke Upload Response File  to git from :  #{response_file} to: #{manifest_git_repo_path}/RESPONSE_FILES ")
	
	%x[ mkdir -p "#{manifest_git_repo_path}/RESPONSE_FILES" ]
	::FileUtils.cp "#{response_file}", "#{manifest_git_repo_path}/RESPONSE_FILES", :verbose => true
	# remove the file in /environmint/tmp
	::FileUtils.rm_f "#{response_file}"
	## Add files to Git
	puts 'Adding deployment prop files to Git'
	%x[ cd #{manifest_git_repo_path} && git add "RESPONSE_FILES/#{environment_name}_mintpress_response.json" && git commit RESPONSE_FILES -m "Updated generated Response iles for #{environment_name.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]

end

# TODO: RB Document this
def compare_versions(v1, v2, file_type_1='.erb', file_type_2='.json', separator_order=1)
	ver1=v1.split('-')[separator_order]
	ver2=v2.split('-')[separator_order]
	if ver1.nil?
		ver1='0.0.0'
	else
		ver1.gsub!(file_type_1, '')
		ver1.gsub!(file_type_2, '')
	end
	if ver2.nil?
		ver2='0.0.0'
	else
		ver2.gsub!(file_type_1, '')
		ver2.gsub!(file_type_2, '')
	end
	return Gem::Version.new(ver2) <=> Gem::Version.new(ver1)
end

# TODO: RB to document this
# Sort recipe files in order
def version_sort!(v, file_type_1='.erb', file_type_2='.json', separator_order=1)
	v.sort! { |v1, v2| compare_versions(v1, v2, file_type_1, file_type_2, separator_order) }
end

# TODO: RB to update the deps, this is no longer valid for 2.6.2
def build_deps(topology_vars)
	wait_for_authenticators()
	wait_for_databases()
	
	## From romil's notes:
	# Run SOA Offline
	# Run Host Offline, Online
	# 5. Run SOA online, UI online
	
	## At least some of these are probably taken care of else where, but we put them hre
	## because we needed them before!
	
	# CIM requires CID to complete for offline stage
	wait_for_asset_complete('obpcim', 'obpcid', 'configure', topology_vars)
	
	# OSB Online Requires Host RCU
	wait_for_server_complete('obposb', 'obpobh', 'admin', 'configure', topology_vars)
	
	# BIP Online Requires Host RCU
	wait_for_server_complete('obpbip', 'obpobh', 'admin', 'configure', topology_vars)
	
	# ODI Online Requires Host RCU
	wait_for_server_complete('obpodi', 'obpobh', 'admin', 'configure', topology_vars)
	
	# UI Online Requires Host RCU
	wait_for_server_complete('obpobu', 'obpobh', 'admin', 'configure', topology_vars)
	
	# Host requires SOA offline to have run to policy re-association
	wait_for_server_complete('obpobh', 'obpsoa', 'admin', 'configure', topology_vars)
	
	# UI requires SOA offline to have run to policy re-association
	wait_for_server_complete('obpobu', 'obpsoa', 'admin', 'configure', topology_vars)
	
	# # RB: Not required for 2.6.2 anymore
	# # UI online requires Host online
	# #wait_for_asset_complete('obpobu', 'obpobh', 'online', topology_vars)
	#
	# # RB: Not required for 2.6.2 anymore
	# # soa online requires host online
	# wait_for_asset_complete('obpsoa', 'obpobh', 'online', topology_vars)
	#
	# # soa online requires host online
	# # OBH requires SOA admin server before configure
	# # satisfies: host offline requires soa offline
	# wait_for_server_complete('obpobh', 'obpsoa', 'admin', 'configure', topology_vars)
	# # OBH requires UI offline before online
	# wait_for_server_complete('obpobh', 'obpobu', 'admin', 'online', topology_vars)
	# # OBU requires SOA offline before configure
	# wait_for_server_complete('obpobu', 'obpsoa', 'admin', 'configure', topology_vars)
	# # OBU requires Host offline before configure
	# wait_for_server_complete('obpobu', 'obpobh', 'admin', 'configure', topology_vars)
	#
	# # SOA requires Host offline before online
	# wait_for_server_complete('obpsoa', 'obpobh', 'admin', 'online', topology_vars)
end

class ::Hash
	def deep_merge!(second)
		merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge!(v2, &merger) : v2 }
		self.merge!(second, &merger)
	end
	
	def deep_clone
		if self.respond_to?('sensitive')
			eval(self.to_s)
		else
			Marshal.load(Marshal.dump(self))
		end
	end
end

# Use this function to clean up the vault after destroy action
def cleanupVault(environment_code, my_topology_vars)
	puts "Cleaning up password vault"
	artifactory_url='https://artifactory1.wpdev.mintpress.io/artifactory/'
	artifactory_pass = Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', 'artifactory', "artifactory_admin"))
	
	%x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/tools/vault"; ]
	%x[ knife data bag show password_vault #{environment_code} -F j > "#{my_topology_vars['common']['git_repo_path']}/tools/vault/#{environment_code}.json" ]
	%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && git add "#{environment_code}.json" && git commit -m "Updated old password files for #{environment_code}.json" && git log -1 --stat && git pull --quiet && git push --quiet]
	%x[ knife data bag delete password_vault #{environment_code} -y ; ]
	%x[ . $HOME/.bash_profile; jfrog rt del --quiet --user=admin --password=#{artifactory_pass} --url #{artifactory_url} "MP-001_CSH-Passwords/#{environment_code}" ]
	%x[ . $HOME/.bash_profile; jfrog rt del --quiet --user=admin --password=#{artifactory_pass} --url #{artifactory_url} "MP-001_CSH-Environment-Details/#{environment_code}" ]
end

# Function to create HTML reports for environments
def generateHTMLReport(environment_code, my_topology_vars)
	puts "Generating HTML output for #{environment_code}"
	if is_running_on_cloud
		sub_folder = 'ocloud'
	else
		sub_folder = 'onprem'
	end
	%x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/tools/reports/#{sub_folder}"; ]
	%x[ . $HOME/.bash_profile; json2xml -i "#{my_topology_vars['common']['git_repo_path']}/chef/obp-environmint-custom/files/data_bags/#{environment_code}_vars.json" -o /tmp/"#{environment_code}"_out.xml && echo '<config>' > /tmp/"#{environment_code}"_updated_out.xml && cat /tmp/"#{environment_code}"_out.xml >> /tmp/"#{environment_code}"_updated_out.xml && echo '</config>' >> /tmp/"#{environment_code}"_updated_out.xml && java -jar "#{my_topology_vars['common']['git_repo_path']}/tools/scripts/saxon9he.jar" /tmp/#{environment_code}_updated_out.xml "#{my_topology_vars['common']['git_repo_path']}/tools/scripts/#{sub_folder}_databag.xslt" > "#{my_topology_vars['common']['git_repo_path']}/tools/reports/#{sub_folder}/#{environment_code}_details.html" ]
	
	%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/reports/#{sub_folder}" && git add "#{environment_code}_details.html" && git commit -m "Updated with HTML file for #{environment_code}" && git log -1 --stat && git pull --quiet && git push --quiet]
	%x[ rm -f /tmp/"#{environment_code}"_out.xml /tmp/"#{environment_code}"_updated_out.xml ; ]

end

# Function to create HTML reports for environments
def generatePasswordVaultZips(environment_code, my_topology_vars)
	puts "Generating Password Vault ZIP files for #{environment_code}"
	ruby_loc='/opt/chefdk/embedded/bin/ruby'
	if is_running_on_cloud
		sub_folder = 'ocloud'
		artifactory_url='https://artifactory1.wpdev.mintpress.io/artifactory/'
		admin_pass = Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', 'zippasswords', "#{environment_code}_admin"))
		readonly_pass = Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', 'zippasswords', "#{environment_code}_readonly"))
		artifactory_pass = Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', 'artifactory', "artifactory_admin"))
		
		%x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/tools/vault"; ]
		%x[ knife data bag show password_vault #{environment_code} -F j > "#{my_topology_vars['common']['git_repo_path']}/tools/vault/#{environment_code}.json" ]
		%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && git add "#{environment_code}.json" && git commit -m "Updated old password files for #{environment_code}.json" && git log -1 --stat && git pull --quiet && git push --quiet]
		%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && #{ruby_loc} csh_decrypt.pwvault.html.rb #{environment_code}.json > #{environment_code}_keepass.html ]
		%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && #{ruby_loc} csh_decrypt.pwvault_readonly.html.rb #{environment_code}.json > #{environment_code}_keepass_readonly.html ]
		%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && zip -e -P "#{admin_pass}" #{environment_code}_keepass.zip #{environment_code}_keepass.html ]
		%x[ cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && zip -e -P "#{readonly_pass}" #{environment_code}_keepass_readonly.zip #{environment_code}_keepass_readonly.html ]
		%x[ . $HOME/.bash_profile; cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && jfrog rt u --user=admin --password=#{artifactory_pass} --url #{artifactory_url} #{environment_code}_keepass.zip MP-001_CSH-Passwords/#{environment_code}/ ; rm -f #{environment_code}_keepass.zip #{environment_code}_keepass.html]
		%x[ . $HOME/.bash_profile; cd "#{my_topology_vars['common']['git_repo_path']}/tools/vault" && jfrog rt u --user=admin --password=#{artifactory_pass} --url #{artifactory_url} #{environment_code}_keepass_readonly.zip MP-001_CSH-Passwords/#{environment_code}/ ; rm -f #{environment_code}_keepass_readonly.zip #{environment_code}_keepass_readonly.html]
		%x[ . $HOME/.bash_profile; cd "#{my_topology_vars['common']['git_repo_path']}/tools/reports/#{sub_folder}" && jfrog rt u --user=admin --password=#{artifactory_pass} --url #{artifactory_url} #{environment_code}_details.html MP-001_CSH-Environment-Details/#{environment_code}/ ]
	
	else
		sub_folder = 'onprem'
	end
	
end

