require 'tempfile'
require 'base64'
require "net/http"
require "uri"

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code = 'OBPVERIFY'

puts "The Run  state of #{_item_code} is  #{node.run_state[_item_code]}"
return unless node.run_state[_item_code]

Chef.node.run_state['deploy_start_time'] = Time.now
puts "Are we running on cloud ? #{is_running_on_cloudFn}"

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####


global_properties = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties'] = global_properties.merge(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)

my_topology_vars.merge!(Hash({'environment_name' => environment_code}))
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))
#my_topology_vars.merge!(my_dep_vars)

my_topology_vars = my_topology_vars.merge(my_dep_vars)
#puts "The Topology Vars  after dep  merge =====> #{my_topology_vars} "
console_props = node.run_state[_item_code.upcase]['properties']
if node.run_state.key?('mintpress_action')
  action = node.run_state['mintpress_action']
else
  action = 'uploadonly'
end
puts "The node run state action #{node.run_state['mintpress_action']}"
puts "The Current Action :: #{action}"

exception_list = ['Start up Services', 'Shutdown Services', 'Setup MintDeploy']
email_sender = my_topology_vars['deployment']['NOTIFY_SENDER']
puts "Sender Email for this Env is : #{email_sender} "
if email_sender.nil?
  email_sender = 'devops@westpac.com.au'
end

#Send Email at the begining of the Orchestration
email_list = my_topology_vars['deployment']['NOTIFY_RECIPIENTS']
puts "Notification Email for this Env is : #{email_list} "
if email_list.nil?
  # TBD remove this .. but we may need a default email
  email_list = 'chandramohan.kannusamy@westpac.com.au'
end

msg = " #{environment_name.upcase} - Action[#{action.upcase}] Initiated \n "
msg << "\n ---- Inputs for this action ------ "
msg << "\n Base Environment     : #{console_props['base_environment']}  \n"
msg << "\n Manifest Commit Hash : #{console_props['manifest_commit_hash'] } \n"

sendEmailFn(environment_name, email_sender,email_list,msg)

#Send Email when the recipe is  completed successfully
Chef.event_handler do
 on :run_completed do
    Chef::Log.info("From the event Success of the recipe==>")
    Chef::Log.info("From the Success Handler")
    msg = "#{environment_name.upcase} - Action[#{action.upcase}] -  Succeeded \n"
    sendEmailFn(environment_name, email_sender,email_list,msg)
  end
end

#Send Email when the recipe failed
Chef.event_handler do
 on :run_failed do
   Chef::Log.info("From the event failure of the recipe==>")
   msg = "#{environment_name.upcase} -  Action[#{action.upcase}] - Failed\n"
   sendEmailFn(environment_name, email_sender,email_list,msg)
 end
end


ssh_key_path = my_topology_vars['deployment']['SSH_KEY']
if ssh_key_path.nil?
  # TBD remove this .. but we may need a default email
  ssh_key_string = ' '
else
  ssh_key_string = "-i " + ssh_key_path
end



Chef::Log.info("Finding the CSH Release Version")
csh_release_version = my_topology_vars['deployment']['CSH_RELEASE_VERSION']
manifest_git_repo_path = my_topology_vars['deployment']['MANIFEST_GIT_STAGE']

Chef::Log.info("This environments is tagged for  CSH Release: #{csh_release_version} ")

#Here is the code to generate deployment validation template
if csh_release_version.nil?
  puts "Missing Release version, could not find matching template"
else
  deployment_validate_template_source = "#{csh_release_version}/deployment-validation/master-validation.erb"
  artifactory_version = "R" + csh_release_version.gsub(".", "")
end

Chef::Log.info("Completed execution of the Custom Build json file")

if action.downcase == 'promote'
    ruby_block "Get the manifest for the commit from base environment" do
      block do
        %x[ cd #{manifest_git_repo_path} && git log -1 --stat && git pull --quiet ]
        puts " Get the Commit Hash & Base Env"


        #puts "Console Properties ==== >  #{console_props} "
        puts "base_environment Input ==== >  #{console_props['base_environment']} "
        puts "manifest_commit_hash Input ==== >  #{console_props['manifest_commit_hash']} "
        temp_file_transfer = "/environmint/tmp/#{environment_name.upcase}_promo_manifest_from_source_#{console_props['base_environment']}.json"
        git_cmd = "git show #{console_props['manifest_commit_hash']}:#{console_props['base_environment'].upcase}/manifest.json > #{temp_file_transfer}"
        puts "The git cmd to be executed #{git_cmd}"
        status = system("cd #{manifest_git_repo_path} && #{git_cmd}")

        puts "The result #{status}"
        if status
          Chef::Log.info("Fetched the commit from the base env successfuly")
        else
          Chef::Log.error("Failed fetch the commit from the base env")
          exit(1)
        end
        promo_manifest_hash = JSON.parse(File.read("#{temp_file_transfer}"))
        node.run_state['promo_manifest_hash'] = promo_manifest_hash
        node.run_state['temp_file_transfer'] = temp_file_transfer
      end
    end


    ruby_block "Pin Cookbook" do
      block do
        #Read the cookbook version from the manifest
        puts "Promo Manifest Hash from Source #{ node.run_state['promo_manifest_hash']}"
        puts "Promo Manifest version from Source #{ node.run_state['promo_manifest_hash']['csh-deployments']}"

        source_cookbook_version = node.run_state['promo_manifest_hash']['csh-deployments']
        #target_env_file = "chef/environment_objects/#{environment_name.downcase}.json"
        target_env_file = "environment_objects/#{environment_name.downcase}.json"

        knife_cmd_output = %x[knife environment show #{environment_name.downcase} -F json -c #{my_topology_vars['deployment']['KNIFE_RB_LOCATION']}]
        knife_env_objects = JSON.parse(knife_cmd_output)
        resultManifest = %x[ cd #{manifest_git_repo_path} && git log -1 --stat && git pull --quiet ]
        puts "Git resultManifest Pull result  : #{resultManifest}"

        resultTechStack = %x[ cd #{my_topology_vars['deployment']['ENVIRONMENTS_OBJ_GIT_PATH']} && git log -1 --stat && git pull --quiet ]
        puts "Git resultTechStack Pull result  : #{resultTechStack}"

        git_env_objects = JSON.parse(File.read("#{my_topology_vars['deployment']['ENVIRONMENTS_OBJ_GIT_PATH']}/#{target_env_file}"))

        if  knife_env_objects['cookbook_versions'] !=  git_env_objects['cookbook_versions']
            puts "Version on Chef Server #{environment_name.downcase} ::  #{knife_env_objects['cookbook_versions']}"
            puts "Version on Git Repo #{environment_name.downcase} :: #{git_env_objects['cookbook_versions']}"

            puts "The Environment Objbects on Chef Server is not in sync with the Git Repo, fix the problems first "
            exit(1)
        else
            puts "Validation between Chef Server and Bit Bucket successful, Proceed with the New Pin"
        end
        puts "Old Env Objects from Git #{git_env_objects}"
        puts "Here is the available version on the source (#{node.run_state[_item_code.upcase]['properties']['base_environment']})::  #{source_cookbook_version}"
        puts "Here is the available version on the target #{environment_name.downcase} :: #{git_env_objects['cookbook_versions']['csh-deployments']}"
        #check if csh-deployments value from the target if it is equal - do nothing

        if source_cookbook_version.nil?
          Chef::Log.error( "There is no cookbook version found on the source manifest file, something wrong ")
          exit(1)
        end

        if git_env_objects['cookbook_versions']['csh-deployments'] != source_cookbook_version
          git_env_objects['cookbook_versions']['csh-deployments'] = source_cookbook_version
          #if different pin the version to the target - knife from file
          #using this intermediate file in place future it may  change over to read from knife
          target_temp_env_file = "/environmint/tmp/env-target-reconstruct-#{environment_name.downcase}.json"
          File.open(target_temp_env_file, "w") {|f| f.write(JSON.pretty_generate(git_env_objects))}
          status = system("knife environment from file #{target_temp_env_file} -c #{my_topology_vars['deployment']['KNIFE_RB_LOCATION']}")
          if status
            puts "::::::::Knife cmd Successful ::::::::"
            status = system("cp #{target_temp_env_file} #{my_topology_vars['deployment']['ENVIRONMENTS_OBJ_GIT_PATH']}/#{target_env_file}  ")
            puts "Copy status result : #{status}"
            result = %x[ cd #{my_topology_vars['deployment']['ENVIRONMENTS_OBJ_GIT_PATH']} && git add "#{target_env_file}" && git commit -am "Updated env objects for #{environment_name.upcase} #{_item_code.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
            puts "Git Commit result  : #{result}"
            ::FileUtils.rm_f "#{target_temp_env_file}"
          else
            Chef::Log.error( "Knife upload failed ")
            exit(1)
          end
        else
          puts "Both Source and Target Cookbooks are same .. do nothing"
        end

      end
    end

    ruby_block "Push source manifest to target" do
    block do
        manifest_git_repo_path = my_topology_vars['deployment']['MANIFEST_GIT_STAGE']
        result = %x[ cd #{manifest_git_repo_path} && git log -1 --stat && git pull --quiet ]
        puts "Status of git pull  #{result}"
        org_manifest_hash = JSON.parse(File.read("#{manifest_git_repo_path}/#{environment_name.upcase}/manifest.json"))
        promo_manifest_hash = node.run_state['promo_manifest_hash']
        temp_file_transfer = node.run_state['temp_file_transfer']

        #puts "We will replace this orginal manifest === > #{org_manifest_hash}"
        #puts "with this manifest on base env === >  #{promo_manifest_hash}"
        status = system("cp #{temp_file_transfer} #{manifest_git_repo_path}/#{environment_name.upcase}/manifest.json")
        if !status
          Chef::Log.error( "Unable to copy the manifest file to the Git repo, something wrong ")
          exit(1)
        end
        result= %x[ cd #{manifest_git_repo_path} && git add "#{environment_name.upcase}/manifest.json" && git commit #{environment_name.upcase} -m "Env manifest Promotion from  (#{node.run_state[_item_code.upcase]['properties']['base_environment']}) to   #{environment_name.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
        puts "Status of git push  #{result}"

      end
    end
end

if action.downcase == 'validate'
ruby_block "fetch manifest for cloud" do

  block do
    manifest_git_repo_path = my_topology_vars['deployment']['MANIFEST_GIT_STAGE']
    %x[ cd #{manifest_git_repo_path} && git log -1 --stat && git pull --quiet ]
    #https://developer.us2.oraclecloud.com/developer03533-a429413/scm/raw/developer03533-a429413_buildmanifest_25999/buildmanifest.git/RB1/manifest.json?revision=master
    Chef::Log.info("TBD provide RO access to every one - read manifest directly now")
    cloud_manifest_file = File.read("/oracle/gitrepos/buildmanifest/#{environment_name.upcase}/manifest.json")
    cloud_manifest_hash = JSON.parse(cloud_manifest_file)
    puts cloud_manifest_hash
    puts "Merge under with   default  attributes"
    node.default.merge! cloud_manifest_hash
    puts "Successfully merged to node default"
    File.open("/environmint/tmp/manifest-fetched-#{environment_name.downcase}.json", "w") {|f| f.write(cloud_manifest_hash)}
    puts "Here is node defaults [  resource print ] #{node.default} "
    node.run_state['manifest'] = cloud_manifest_hash

  end
  only_if "#{is_running_on_cloudFn}"
end


ruby_block "fetch manifest for on prem" do
  block do
    Chef::Log.info("Fetching Manifest from git ..")

    manifest_uri = URI.parse("#{my_topology_vars['deployment']['MANIFEST_REPO_URL']}/raw/#{environment_name.upcase}/manifest.json?at=refs%2Fheads%2Fmaster")
    response = Net::HTTP.get_response(manifest_uri)
    Chef::Log.info("Response from the request #{response.code}")
    if response.code == "200"
      Chef::Log.info("Fetched the manifest file successfully")
      puts response.body
      manifest_vars = JSON.parse(response.body)

      puts "Merge under with   default  attributes"
      node.default.merge! manifest_vars
      puts "Successfully merged to node default"
      File.open("/environmint/tmp/manifest-fetched-#{environment_name.downcase}.json", "w") {|f| f.write(manifest_vars)}
      puts "Here is node defaults [  resource print ] #{node.default} "
      node.run_state['manifest'] = manifest_vars
    else
      Chef::Log.error("Failed to fetch the manifest file")
      exit(1)
    end
  end
  not_if "#{is_running_on_cloudFn}"
end


  ruby_block "generate artifact urls" do
    block do
      url_list = Array.new
      manifest_vars = node.run_state['manifest']
      cemli_release_path = manifest_vars['cemli_release_path'].gsub('.', '/')
      puts cemli_release_path
      map_artifactnames = Hash["business_config" => "extensionsbusinessconfig", "soa" => "extensionssoacomp", "documaker_dayZero" => "extensionsdoc", "odi" => "extensionsodi", "host" => "extensionshost", "access_policies" => "extensionspolicystoresetup", "osb" => "extensionsosb", "bip" => "extensionsreports", "humanTask" => "extensionsht", "oam" => "extensionspolicystoresetup", "ui" => "extensionsui", "db_incremental" => "extensionsdbincremental", "documaker_cemli" => "extensionsdoc", "soaDynamicGroupApproval" => "extensionssoadynamicapproval", "odi_batch" => "extensionsobpscripts", "bam" => "extensionsbam", "urm" => "extensionsurm", "obiee_incremental" => "OBIEEE"]
      manifest_vars['deployments'].each do |key, data|
        asset_obj = key
        mint_plan = data['mint_plan']
        manifest_ext_version = data['extension_version']

        puts asset_obj
        puts mint_plan
        puts manifest_ext_version

        cemli_artifact_path = my_topology_vars['deployment']['CEMLI_ARTIFACTORY_URL'] + "/" + cemli_release_path
        puts "Cemli release artifact path"
        puts cemli_artifact_path
        fullPath = cemli_artifact_path +"/" + map_artifactnames[asset_obj] + "/" + manifest_ext_version + "/" + map_artifactnames[asset_obj] + "-" + manifest_ext_version + ".pom"
        puts fullPath
        url_list.push fullPath

      end
      url_hash = Hash({'urls' => url_list})
      puts "Here is the list of Artifactory URL (hash) #{ url_hash.to_yaml } "
      f = File.open("/tmp/urls.yml", 'w')
      f.write url_hash.to_yaml
      f.close
    end
    not_if "#{is_running_on_cloudFn}"
  end

  template 'App Deployment Validation template' do
    source "#{deployment_validate_template_source}"
    path "/environmint/tmp/gen-validate-deployment_#{environment_name}.json"
    variables(
        variables(
            :dataBag => my_topology_vars,
            :environment_name => environment_name,
            :shell_init_string => "set -e ; source /home/oracle/.bash_profile ; ",
            :script_init_string => "set -e",
            :ssh_key_string => ssh_key_string
        )
    )
    mode '0644'
  end

  runtime_url = URI.parse("#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}")
  app_admin_user = my_topology_vars['deployment']['RUNTIME_APP_ADMIN_USER']


  ruby_block "Upload to Runtime" do
    block do
      payload_data = ::File.open("/environmint/tmp/gen-validate-deployment_#{environment_name}.json").read()
      json_data = JSON.parse(payload_data)
      baseplan = json_data['name'].gsub('_', '').gsub(' ', '').upcase
      baseurl = "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/browse/#{baseplan}"
      result = RestClient::Request.execute(method: :post, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', "#{app_admin_user}", 'password'))}", url: "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/envmint/1.0/importProject", payload: payload_data, headers: {'Content-Type' => 'application/json'})
      puts "Uploaded with #{result}"
      if result.include? "Successfully imported Bamboo project"
        puts "Import to Runtime Successful"
        puts baseurl
        node.run_state['baseurl'] = baseurl
        Chef::Log.info("Here is the base url after import  ... #{node.run_state['baseurl']}")
        #Below update console url needs to be fixed
        #update_console_urls_for_catalogitem(node['environmint']['orchestration']['key'], _item_code.upcase, baseurl)
      else
        Chef::Log.error( "Failed to import json to Mintpress Runtime")
        exit(1)
      end
    end
  end

  ruby_block "parseme" do
    block do
      puts "RT Instance to invoke #{runtime_url}"
      json_data = JSON.parse(::File.open("/environmint/tmp/gen-validate-deployment_#{environment_name}.json").read())
      baseplan = json_data['name'].gsub('_', '').gsub(' ', '').upcase
      steplist = []
      json_data['plans'].each do |p|
        cplan = p['name']
        puts "The plan : #{cplan}"
        steplist << cplan
      end
      steplist << 'Artifact Validation'
      steplist << 'Server Status Validation'
      node.run_state['baseplan'] = baseplan
      node.run_state['steplist'] = steplist
      puts "PROJECT PLAN IS - #{node.run_state['baseplan']}"
      puts "STEPS ARE #{node.run_state['steplist']}"
    end
  end

  mintpress_runtime "run-deployment" do
    puts "Run validation plans now .."
    protocol runtime_url.scheme
    url runtime_url.host
    port runtime_url.port
    base_path runtime_url.path
    project_list lazy {[node.run_state['baseplan']]}
    steps lazy {node.run_state['steplist']}
    parallel_builds 10
    username "#{app_admin_user}"
    password "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress', "#{app_admin_user}", 'password'))}"
  end

end
ruby_block "All Done" do
  block do
    puts "Completed all steps "
  end
end