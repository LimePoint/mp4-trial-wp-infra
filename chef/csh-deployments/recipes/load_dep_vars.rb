require 'json'
require 'tempfile'
require 'base64'
require 'net/ssh'
require 'net/ping'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

def uploadFiles2Git(env_name, tempfile, vars)
    Chef::Log.info("Invoke uplaod of new/updated #{tempfile} to git ")
    ruby_block "upload new/updated files to git " do
        block do
            if vars['common']['git_commit_on_upload'].downcase == 'true'
                case
                when tempfile.match('json')
                    current_branch = %x[ cd "#{vars['common']['git_repo_path']}"; git rev-parse --abbrev-ref HEAD;].chomp
                    %x[ mkdir -p "#{vars['common']['git_repo_path']}/chef/csh-deployments/files/data_bags" ]
                    ::FileUtils.cp_r "/tmp/#{tempfile}", "#{vars['common']['git_repo_path']}/chef/csh-deployments/files/data_bags/", :verbose => true
                    ## Add files to Git
                    puts 'Adding deployment prop file to Git'
                    %x[ cd "#{vars['common']['git_repo_path']}" && git pull --quiet && git add "chef/csh-deployments/files/data_bags/#{tempfile}" && git commit -am "Updated/Generated deployment variables file for #{env_name.upcase}"; git log -1 --stat && git pull --quiet && git push origin #{current_branch} --quiet && /opt/chefdk/embedded/bin/knife cookbook upload -o #{vars['common']['git_repo_path']}/chef csh-deployments ]
                when tempfile.match('properties')
                    current_branch = %x[ cd "#{vars['common']['git_repo_path']}/../buildmanifest"; git rev-parse --abbrev-ref HEAD;].chomp
                    %x[ mkdir -p "#{vars['common']['git_repo_path']}/../buildmanifest/#{env_name.upcase}" ]
                    ::FileUtils.cp_r "/tmp/#{env_name}/#{tempfile}", "#{vars['common']['git_repo_path']}/../buildmanifest/#{env_name.upcase}/", :verbose => true
                    ## Add files to Git
                    puts 'Adding OSB deployment properties to buildmanifest'
                    %x[ cd "#{vars['common']['git_repo_path']}/../buildmanifest" && git pull --quiet && git add "#{env_name.upcase}/#{tempfile}" && git commit -am "Updated/Added OSB deployment properties file for #{env_name.upcase}"; git log -1 --stat && git pull --quiet && git push origin #{current_branch} --quiet]
                end
			end
		end
	end
end

def createDeploymenProps(env_name, template_src, topology_vars)
    begin
        Chef::Log.info("Invoke deployment property creation method..")
        Chef::Log.info("Get source template from #{template_src}")
        ## Declaring all the necessary variables for this here
        odi_host = topology_vars['obpodi']['hostnameList'][0]
        odi_encoder = "/oracle/app/binaries/runtime/obpodi/domains/obpodi_domain/bin/encode.sh"
        odi_encoded_dbpwd = nil
        odi_encoded_wlspwd = nil
        ssh_keyfile="/home/mintpress/.ssh/id_rsa"
        pwd_vault = topology_vars['common']['password_vault_name']
        obpobh_dbpwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/obpobh/OBPHOST").value)
        obpobh_wlspwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/obpobh/weblogic").value)
        host_4_DCMS = topology_vars['obpipm']['hostnameList'][0]
        temp_fn = "#{env_name}_dep_vars.json"

# get the odi encoded string only if the ODI host is rechable and has the odi encoder available

        if Net::Ping::TCP.new(odi_host,'22').ping?
            Net::SSH.start(odi_host, "mintpress", :keys => [ssh_keyfile], :verify_host_key => Net::SSH::Verifiers::Null.new) do |ssh|
              result=ssh.exec!("sudo -u oracle 'if [ -e #{odi_encoder} ]; then echo -n 0; fi'")
              if result=='0'
                puts "Encoding the passwords with ODI encoder"
                odi_encoded_dbpwd = ssh.exec!("sudo -u oracle '#{odi_encoder} -INSTANCE=OracleDISAgent1 #{obpobh_dbpwd} 2> /dev/null|tail -1'").rstrip
                odi_encoded_wlspwd = ssh.exec!("sudo -u oracle '#{odi_encoder} -INSTANCE=OracleDISAgent1 #{obpobh_wlspwd} 2> /dev/null|tail -1'").rstrip
              end
            end
        end
        template "Generating Deployment Vars for #{env_name}" do
            source template_src
            path "/tmp/#{temp_fn}"
            variables (
                variables(
                    :environment => env_name,
                    :obpipm => host_4_DCMS,
                    :odi_encoded_obpobh_db_pwd => odi_encoded_dbpwd,
                    :odi_encoded_obpobh_wls_pwd => odi_encoded_wlspwd)
                )
            mode '0644'
            end.run_action(:create)
        uploadFiles2Git(env_name, temp_fn, topology_vars)
    rescue Exception
        Chef::Log.error("Fatal error while creating deployment properties #{template_src}")
        raise
    end
end

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
env_name = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{env_name}_vars.json"))
template_src="opcdev_dep_vars.json.erb"
#osb_props_template="osb_dep.properties.erb"

    directory "/tmp/#{env_name}" do
    end

=begin
    template "Creating or Updating OSB properties for #{env_name}" do
        source osb_props_template
        path "/tmp/#{env_name}/#{osb_props_template.gsub('.erb','')}"
        variables (
            variables(
            :environment => env_name,
            :topology_vars => my_topology_vars
            )
        )
        mode '0640'
    end
    uploadFiles2Git(env_name, osb_props_template.gsub('.erb',''), my_topology_vars)
=end

    createDeploymenProps(env_name,template_src,my_topology_vars)
