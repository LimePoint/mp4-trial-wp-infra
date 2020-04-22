require 'tempfile'
require 'base64'
require "net/http"
require "uri"

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPCOMP'

puts "The Run  state of #{_item_code} is  #{node.run_state[_item_code]}"
return unless node.run_state[_item_code]
Chef.node.run_state['deploy_start_time'] = Time.now
puts "Are we running on cloud ? #{is_running_on_cloudFn}"

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####


global_properties = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.merge(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)

my_topology_vars.merge!(Hash({'environment_name' => environment_code}))
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))
#my_topology_vars.merge!(my_dep_vars)

my_topology_vars = my_topology_vars.merge(my_dep_vars)
puts "The Topology Vars  after dep  merge =====> #{my_topology_vars} "
lp_cd_home="/backup/cont-delivery"
#Start of Auto Pinning of Cookbook to environment from manifest json
knifeRBPath= is_running_on_cloudFn ? "/home/mintpress/.chef/knife.rb"  :  "/home/mintpress/mintpress/.chef/knife-csh.rb"
manifest_git_repo_path = my_topology_vars['deployment']['MANIFEST_GIT_STAGE']
#pinCookbook(manifest_git_repo_path,environment_name,my_topology_vars['deployment']['KNIFE_RB_LOCATION'])
pinCookbook(manifest_git_repo_path,environment_name,knifeRBPath)
#End of Auto Pinning of Cookbook to environment from manifest json
if node.run_state.key?('mintpress_action')
    action = node.run_state['mintpress_action']
else
    action = 'uploadonly'
end
puts "The Current Action :: #{action}"

if is_running_on_cloudFn
    syncManifestCommit(environment_name.upcase, my_topology_vars, lp_cd_home)
    include_recipe "::load_dep_vars"
else
    syncManifestCommit(environment_name.upcase, my_topology_vars, lp_cd_home)
end

exception_list = ['Start up Services','Shutdown Services','Setup MintDeploy','Restart Services','Start Documaker Services','Deploy Documaker']
#Send Email at the begining of the Orchestration
email_list = my_topology_vars['deployment']['NOTIFY_RECIPIENTS']
puts "Notification Email for this Env is : #{email_list} "
if email_list.nil?
    # TBD remove this .. but we may need a default email
    email_list = 'chandramohan.kannusamy@westpac.com.au'
end

ssh_key_path = my_topology_vars['deployment']['SSH_KEY']
if ssh_key_path.nil?
  # TBD remove this .. but we may need a default email
  ssh_key_string = ' '
else
  ssh_key_string = "-i " + ssh_key_path
end

#Send Email at the begining of the Orchestration
email_sender = my_topology_vars['deployment']['NOTIFY_SENDER']
puts "Sender Email for this Env is : #{email_sender} "
if email_sender.nil?
  # TBD remove this .. but we may need a default email
  email_sender = 'devops@westpac.com.au'
end

if ( action.downcase == 'deploy' and  (environment_name =~ /^psp/ or environment_name =~ /^prd/ ) )
    msg = "#{environment_name.upcase} - Deployment  Action[#{action.upcase}] Will be ABORTED for the critical environments \n"
    sendEmailFn(environment_name, email_sender,email_list,msg)
    puts "We cannot execute deploy action on these environment - psp* and prd*"
    exit(1)
end

#TBD change this to deploy only later, no need for notification on upload
if action.downcase == 'deploy' or action.downcase == 'uploadonly'
    msg = "#{environment_name.upcase} - Deployment  Action[#{action.upcase}] Initiated \n"
    sendEmailFn(environment_name, email_sender,email_list,msg)
end

#Send Email when the recipe is  completed successfully
Chef.event_handler do
 on :run_completed do
    Chef::Log.info("From the event Success of the recipe==>")
    baseurl = Chef.node.run_state['baseurl']
    deploy_state = Chef.node.run_state['deploy_state']
    if action.downcase == 'uploadonly'
        #TBD  for test only
        Chef::Log.info("From the Success (upload only action) deploy_state =  #{deploy_state}  & baseurl = #{baseurl}")
        #handleResponseFileFn(environment_name, "Success",my_topology_vars)

        msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}] - [#{Chef.node.run_state['manifest']['build_version']}]  Succeeded \nPlan URL: : #{baseurl} \n"
        sendEmailFn(environment_name, email_sender,email_list,msg)
    end
    if action.downcase == 'deploy'
        Chef::Log.info("From the Success (deploy action ) deploy_state =  #{deploy_state}  & baseurl = #{baseurl}")
        app_admin_user = my_topology_vars['deployment']['RUNTIME_APP_ADMIN_USER']
        result = wait4_inprogress_with_statsFn( Chef.node.run_state['baseplan'], my_topology_vars['deployment']['RUNTIME_IMPORT_URL'], app_admin_user, Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password')), Chef.node.run_state['comp_build_array'] + exception_list)
        if result.nil?
            puts "damn - fatal exception inside wait4_inprogress_with_statsFn"
            exit(1)
        else
            puts "Here is the result =>" + JSON.pretty_generate(result)
            puts "Invoke the Response File handling  .."
            handleResponseFileFn(environment_name, "Success", my_topology_vars,result )
        end


        msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}] - [#{Chef.node.run_state['manifest']['build_version']}]  Succeeded \nPlan URL: : #{baseurl} \n"
        sendEmailFn(environment_name, email_sender,email_list,msg)
    end
 end
end

#Send Email when the recipe failed
Chef.event_handler do
 on :run_failed do
   Chef::Log.info("From the event failure of the recipe==>")
   #This failure is upload only , not so significant for wait or response file, just send email
   if action.downcase == 'uploadonly'
       #TBD  for test only
       Chef::Log.info("From the Failure (upload only action) deploy_state =  #{deploy_state}  & baseurl = #{baseurl}")

       msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}] - [#{Chef.node.run_state['manifest']['build_version']}]  Failed \n"
       sendEmailFn(environment_name, email_sender,email_list,msg)
   end
   #When the pipeline failed we need to handle wait for in progress, metric collection and emails handling in detail
   deploy_state = Chef.node.run_state['deploy_state']
   baseurl = Chef.node.run_state['baseurl']
   Chef::Log.info("From the event failure : deploy_state =  #{deploy_state}  & baseurl = #{baseurl}")

   #Handle  generating response file only if the pipeline has started, completed   or do nothing
   case deploy_state when "initiated", "deployed" then
    Chef::Log.info("Need to handle Response file as deployment state is initiated")

     msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}] - [#{Chef.node.run_state['manifest']['build_version']}]  Failed - MintPress waiting for other plans in-progress (if any) \nPlan URL: : #{baseurl} \n"
     msg << "\n (1) One of the deployment plan has failed. Component Deployment List : #{Chef.node.run_state['comp_build_array'] } \n"
     msg << "\n (2) MintPress Orchestration will wait for any IN-PROGRESS build and notify soon with a response file. (The Maximum wait period is 2 hours) \n"
     msg << "\n (3) Orchestration will wait for only the components triggered by automation. All manual builds will be ignored. \n"
     sendEmailFn(environment_name.upcase, email_sender,email_list,msg)

     app_admin_user = my_topology_vars['deployment']['RUNTIME_APP_ADMIN_USER']
     result = wait4_inprogress_with_statsFn( Chef.node.run_state['baseplan'], my_topology_vars['deployment']['RUNTIME_IMPORT_URL'], app_admin_user, Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password')), Chef.node.run_state['comp_build_array'] + exception_list)
     puts "Inspect Result " + result.inspect

        if result.nil?
            puts "damn - fatal exception inside wait4_inprogress_with_statsFn"
            exit(1)
        else
            puts "Here is the result " + JSON.pretty_generate(result)
        end

    handleResponseFileFn(environment_name, "Failed", my_topology_vars, result)
   end

   msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}] - [#{Chef.node.run_state['manifest']['build_version']}]  Failed \nPlan URL: : #{baseurl} \n"
   msg << "\n (1) Deployment Failed!!. Component Deployment list without mint deploy, default plans: #{Chef.node.run_state['comp_build_list_trim']} \n"
   msg << "\n (2) Deployment Validation  Status : #{Chef.node.run_state['deploy_validation']}.\n"
   msg << "\n (3) Please check the response file for failed component deployments.\n"
   sendEmailFn(environment_name.upcase, email_sender,email_list,msg)
   puts "All Emails sent ======>"
 end
end

asset_vars = my_topology_vars[_item_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']

Chef::Log.info("Executing Template ..")

#puts "Dumping topovars #{my_topology_vars}"

app_admin_user = my_topology_vars['deployment']['RUNTIME_APP_ADMIN_USER']
Chef::Log.info(" Runtime App Admin User ::  #{app_admin_user} ")
password_from_vault = PasswordVault.get_password('mintpress',app_admin_user,'password')
PasswordVault.put_password('mintpress',app_admin_user,'password', password_from_vault)

artifact_user = my_topology_vars['deployment']['ARTIFACTORY_USER']
Chef::Log.info(" Runtime App Admin User ::  #{artifact_user} ")
artifact_pwd_from_vault = PasswordVault.get_password('mintpress',artifact_user,'password')
PasswordVault.put_password('mintpress',artifact_user,'password', artifact_pwd_from_vault)

#Get the manifest file from the Repository and Merge
if action.downcase == 'deploy' or action.downcase == 'uploadonly'

    Chef::Log.info("Finding the CSH Release Version")
    csh_release_version = my_topology_vars['deployment']['CSH_RELEASE_VERSION']
    Chef::Log.info("This environments is tagged for  CSH Release: #{csh_release_version} " )

    #Here is the code to generate deployment Properties
    if csh_release_version.nil?
        deployment_prop_template_source  = "deployment"
        deployment_build_template_source  = "deployment-v2/master-deploy.json.erb"
        artifactory_version = "R11"
    else
        deployment_prop_template_source  = "#{csh_release_version}/deployment-props"
        deployment_build_template_source  = "#{csh_release_version}/deployment-build/master-deploy.json.erb"
        artifactory_version = "R"+csh_release_version.gsub(".","")
    end

    Chef::Log.info("The artifactory version for this Env is : #{artifactory_version}" )
    tmp_folder="/limepoint/runTime/tmp/deployment/deployment-prop"
    createDeploymenPropsFn(environment_name, deployment_prop_template_source, my_topology_vars, artifactory_version)
    #zipAndPackageArtifactoryFn(environment_name, tmp_folder, my_topology_vars, artifactory_version, "CSH.1.2")
    Chef::Log.info("Deployment  template from this folder : #{deployment_prop_template_source}" )

    Chef::Log.info("This Orchestration will use template from this folder : #{deployment_build_template_source}" )

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
          File.open("/limepoint/runTime/tmp/deployment/manifest-fetched-#{environment_name.downcase}.json","w") {|f| f.write(cloud_manifest_hash)}
          puts "Here is node defaults [  resource print ] #{node.default} "
          result=%x[knife environment show #{environment_name.downcase} -F json -c ~/.chef/knife.rb] #get the cookbook pinned to the environment
          iparse=JSON.parse(result)
          cookbookVersion=(iparse["cookbook_versions"]["csh-deployments"].eql?nil) ? "latest" : iparse["cookbook_versions"]["csh-deployments"].delete("= ")
          puts "This is tactical fix to fix mintdeploy version #{cookbookVersion}"
          puts "Before Update \n #{cloud_manifest_hash}"
          #Checking if cookbook version is latest and manifest json if the mintdeploy_version is less than "8.1.3" and csh-deployments version is less than 8.2.3 
          if cookbookVersion.include?("latest") && cloud_manifest_hash["mintdeploy_version"]<"8.1.3"
               cloud_manifest_hash["mintdeploy_version"]="8.1.3"
          end
          puts "after Update \n #{cloud_manifest_hash}"
          node.run_state['manifest']=cloud_manifest_hash
        end
        only_if "#{is_running_on_cloudFn}"
    end

    ruby_block "fetch manifest for on prem" do
        block do
            Chef::Log.info("Fetching Manifest from git ..")

            manifest_uri = URI.parse( "#{my_topology_vars['deployment']['MANIFEST_REPO_URL']}/raw/#{environment_name.upcase}/manifest.json?at=refs%2Fheads%2Fmaster")
            response = Net::HTTP.get_response(manifest_uri)
            Chef::Log.info("Response from the request #{response.code}")
            if response.code == "200"
                Chef::Log.info("Fetched the manifest file successfully")
                puts response.body
                manifest_vars = JSON.parse(response.body)

                puts "Merge under with   default  attributes"
                node.default.merge! manifest_vars
                puts "Successfully merged to node default"
                File.open("/limepoint/runTime/tmp/deployment/manifest-fetched-#{environment_name.downcase}.json","w") {|f| f.write(manifest_vars)}
                puts "Here is node defaults [  resource print ] #{node.default} "
                node.run_state['manifest']=manifest_vars
            else
                Chef::Log.error("Failed to fetch the manifest file")
                exit(1)
            end
        end
        not_if "#{is_running_on_cloudFn}"
    end

    ruby_block "fetch response file for cloud" do
      block do
      #Keep this until we read the manifest as raw
      #https://developer.us2.oraclecloud.com/developer03533-a429413/scm/raw/developer03533-a429413_buildmanifest_25999/buildmanifest.git/RB1/manifest.json?revision=master
        Chef::Log.info("TBD provide RO access to every one - read response file directly now")
        manifest_git_repo_path = my_topology_vars['deployment']['MANIFEST_GIT_STAGE']
        %x[ cd #{manifest_git_repo_path} && git log -1 --stat && git pull --quiet ]

        cloud_response_file_path  = "#{manifest_git_repo_path}/RESPONSE_FILES/#{environment_name}_mintpress_response.json"
        Chef::Log.info("Cloud Response File #{cloud_response_file_path}")
        if File.exist?(cloud_response_file_path)
          cloud_response_file= File.read(cloud_response_file_path)
          cloud_response_vars = JSON.parse(cloud_response_file)
          puts cloud_response_vars
          File.open("/limepoint/runTime/tmp/deployment/response-fetched-#{environment_name.downcase}.json","w") {|f| f.write(cloud_response_vars)}
          puts "Here is response file for cloud [  resource print ] #{cloud_response_vars} "
          node.run_state['response_file']=cloud_response_vars
        else
          Chef::Log.info("No Response File on the cloud , it is a brand new environment")
          resp_vars_init = Hash[ "environment" => "#{environment_name}", "deployments" => {} ]
          node.run_state['response_file']=resp_vars_init
        end

        puts "Here is where we are updating #{my_topology_vars['uuid']}  -  #{my_topology_vars['code']} -  #{_item_code} "

        update_console_urls_for_catalogitem2(my_topology_vars['uuid'], my_topology_vars['code'], [{"itemCode" => _item_code, 'name' => "deployment_plan", 'description' => 'deployment url', 'url' => "test deployment url"}])
        #update_console_urls_for_catalogitem2(node['environmint']['orchestration']['key'], _item_code, "Fetched response from On-Prem repository - Successfully")
      end
      only_if "#{is_running_on_cloudFn}"
    end

    ruby_block "fetch response file on prem" do
        block do
            Chef::Log.info("Fetching Respone file  from git on prem ..")
            manifest_response_uri = URI.parse( "#{my_topology_vars['deployment']['MANIFEST_REPO_URL']}/raw/RESPONSE_FILES/#{environment_name.downcase}_mintpress_response.json?at=refs%2Fheads%2Fmaster")
            response = Net::HTTP.get_response(manifest_response_uri)
            Chef::Log.info("Response from the request #{response.code}")
            if response.code == "200"
                Chef::Log.info("Fetched the Response file successfully")
                puts response.body
                response_vars = JSON.parse(response.body)
                puts "Copy File to tmp"
                File.open("/limepoint/runTime/tmp/deployment/#{environment_name.downcase}_mintpress_response.json","w") {|f| f.write(response_vars)}
                puts "Here is response file [  resource print ] #{response_vars} "
                node.run_state['response_file']=response_vars
            else
                Chef::Log.info("No Response File, it is a brand new environment")
                resp_vars = Hash[ "environment" => "#{environment_name}", "deployments" => {} ]
                node.run_state['response_file']=resp_vars

            end

            #update_console_urls_for_catalogitem2(node['environmint']['orchestration']['key'], _item_code, "Fetched manifest from Cloud repository - Successfully")

        end
        not_if "#{is_running_on_cloudFn}"
    end

    ruby_block "Compare Component Deploy" do
        block do
            Chef::Log.info("Compare components with manifest and response files")
            manifest_vars=node.run_state['manifest']
            response_vars=node.run_state['response_file']
            comp_build_array = Array.new
            asset_array = Array.new
            Chef::Log.info("From Compare - manifest_vars : #{manifest_vars}")
            Chef::Log.info("From Compare - response_vars : #{response_vars}")
            # Loop through the manifest vars & pick up the CEMLI VERSION
            # Check the right attribute in the response file ( last commited)
            # if they are not equal , it is a candidate for deployment
            #create a array of  diff components and new
            puts "Data in manifest-vars #{manifest_vars['deployments']}"
            manifest_vars['deployments'].each do | key, data|
                 asset_obj = key
                 mint_plan = data['mint_plan']
                 manifest_ext_version = data['extension_version']
                 puts asset_obj
                 puts mint_plan
                 puts manifest_ext_version

                 enable_orchestration = 'true'
                 unless data['orchestrate'].nil?
                    puts "Orchestrate flag set here for this component"
                    enable_orchestration =   data['orchestrate']
                 end

                 puts "Enable Orchestration is ==========> : #{enable_orchestration}"

                 target_reponse_asset = response_vars['deployments'][asset_obj]
                 Chef::Log.info("Target Response Asset #{target_reponse_asset}")
                 unless target_reponse_asset.nil?
                    #data exists in the response file, see if there is a diff  for version
                    resp_success_version = response_vars['deployments'][asset_obj]['success_version']
                    Chef::Log.info("Target Response Ext Version #{resp_success_version}")
                    if ( manifest_ext_version == resp_success_version  or  enable_orchestration == 'false')
                        Chef::Log.info("From Compare v2- Equal  - Both are equal or enable_orchestration is false -   Ignore this for #{asset_obj} - manifest #{manifest_ext_version} and response #{resp_success_version} ")
                    else
                        Chef::Log.info("From Compare v2- Here is the comp to deploy  for #{asset_obj} - manifest #{manifest_ext_version} and response #{resp_success_version} ")
                        comp_build_array << mint_plan
                        asset_array << asset_obj
                    end
                 else
                    #no response data - should be new , just add it but check if it needs to be ignored for orchestration
                    if (enable_orchestration == 'true')
                        Chef::Log.info("New Environment, but needs to orchestrated")
                        comp_build_array << mint_plan
                        asset_array << asset_obj
                    else
                        Chef::Log.info("Even if it is New Environment, orchestrate is explicitly set to false")
                    end
                 end

            end
            comp_build_array.delete(nil)
            asset_array.delete(nil)
            Chef::Log.info("From Compare - The Final list of Component build items: #{comp_build_array}")
            #Chef::Log.info("From Compare - The Final list (Cleaned) of Component build items: #{comp_build_array.compact!}")
            node.run_state['comp_build_list_trim']=comp_build_array.clone

            node.run_state['comp_build_array']=comp_build_array
            node.run_state['asset_array']=asset_array
            Chef::Log.info("Probe the run state of comp build array #{node.run_state['comp_build_array']}")

        end
    end
    #Find the next Version for the project name
    ruby_block "Find Project-Build  Version" do
      block do
        git_repo_path = my_topology_vars['common']['git_repo_path']
        %x[ cd #{git_repo_path} && git log -1 --stat && git pull --quiet ]
        Chef::Log.info("Pulled latest files for the app deployment")
        app_dep_file_path = "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/#{environment_name}_app_deployments.json"
        if (::File.exist?(app_dep_file_path))
            prev_app_deployment_content = File.read( app_dep_file_path )
            prev_app_hash = JSON.parse(prev_app_deployment_content)
            prev_proj_name = prev_app_hash['name']
        else
            prev_proj_name = "none"
        end
        node.run_state['prev_proj_name']=prev_proj_name
        puts "Previous Project Name from Git Repo :: #{prev_proj_name}"
      end
    end

    template 'app deploy template' do
      source "#{deployment_build_template_source}"
      path "/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json"
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

    ruby_block "Remove Unwanted Plans" do
      block do
        payload_data=::File.open("/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json").read()
        result_parsed=JSON.parse(payload_data)
        baseplan=result_parsed['name'].gsub('_','').gsub(' ','').upcase
        puts "The base plan name ::  #{baseplan}"
        #puts result['plans']['plan']
        Chef::Log.info("Probe the run state of comp build array before Delete  #{node.run_state['comp_build_array']}")
        combined_list = node.run_state['comp_build_array'] + exception_list
        combined_list << "Disable All Plans"
        puts "Check the plans that need to be deleted here #{combined_list} "
        puts "Array Before :: #{result_parsed["plans"]}"
        result_parsed["plans"].delete_if do |plan|
          puts "Running delete action now  .. iterate through the array of plans"
          split_name = plan["name"].split('--')[1].strip
          unless (combined_list.include?(split_name)  )
            p "Keep this  Plan #{split_name}"
            true
          else
            p "Removing Plan #{split_name}"
            false
          end
        end
        puts "Array After :: #{result_parsed["plans"]}"
        File.open("/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json","w") do |f|
          f.write(JSON.pretty_generate(result_parsed))
        end
      end
    end

    ruby_block "Upload to Runtime" do
        block do
          payload_data=::File.open("/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json").read()
          json_data=JSON.parse(payload_data)
          baseplan=json_data['name'].gsub('_','').gsub(' ','').upcase
          baseurl= "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/browse/#{baseplan}"
          puts "Base URL   : #{baseurl}"

          result=RestClient::Request.execute(method: :post, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}", url: "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/envmint/1.0/importProject", payload: payload_data, headers: {'Content-Type' => 'application/json' })
          puts "Uploaded with #{result}"
          if result.include? "Successfully imported Bamboo project"
             puts "Import to Runtime Successful"
             puts baseurl
             node.run_state['baseurl']=baseurl
             node.run_state['baseplan']=baseplan
             Chef::Log.info("Here is the base url after import  ... #{node.run_state['baseurl']}")
             #update_console_urls_for_catalogitem(node['environmint']['orchestration']['key'], _item_code.upcase, baseurl)
             #update_console_urls_for_catalogitem2(node['environmint']['orchestration']['key'], _item_code, "Mintpress Runtime URL #{node.run_state['baseurl']}")
          else
            Chef::Log.error("Failed to import json to Mintpress Runtime")
            exit(1)
          end

        end
    end

    ruby_block "Disable Other Plans" do
        block do
          payload_data=::File.open("/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json").read()
          json_data=JSON.parse(payload_data)
          baseplan=json_data['name'].gsub('_','').gsub(' ','').upcase
          puts baseplan
          puts "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/api/latest/project/#{baseplan}.json&expand=plans"

          result=RestClient::Request.execute(method: :get, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}", url: "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/api/latest/project/#{baseplan}.json?expand=plans",  headers: {'Content-Type' => 'application/json' })
          puts "The Project plan with #{result}"
          #puts result['plans']['plan']
          Chef::Log.info("Probe the run state of comp build array before Disable #{node.run_state['comp_build_array']}")
          combined_list = node.run_state['comp_build_array'] + exception_list
          puts "Check the plans that need to be enabled here #{combined_list} "
          result_parsed = JSON.parse(result)
          result_parsed["plans"]["plan"].each do |plan|
            split_name = plan["shortName"].split('--')[1].strip
            puts "The comp build name after split #{split_name}"

            #prod and psp plans need to disabled ..why!!!! there shoudnt be any pets in devops
            #Remove first part of the if condition later
            #Tactical
            if (environment_name =~ /^psp/ or environment_name =~ /^prd/  )
                    p "Disabling Plan "+plan["key"]
                    result_action = RestClient::Request.execute(method: :delete, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}", url: "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/api/latest/plan/#{plan["key"]}/enable",  headers: {'Content-Type' => 'application/json' })
                    puts result_action
            else
                unless (combined_list.include?(split_name)  )
                    p "Disabling Plan "+plan["key"]
                    result_action = RestClient::Request.execute(method: :delete, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}", url: "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/api/latest/plan/#{plan["key"]}/enable",  headers: {'Content-Type' => 'application/json' })
                    puts result_action
                end
            end
          end
        end
    end

    ruby_block "upload files to git " do
        block do
            if  my_topology_vars['common']['git_commit_on_upload'].downcase == 'true'
                %x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}" ]
                ::FileUtils.cp "/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json", "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/#{environment_name}_app_deployments.json", :verbose => true
                # remove the file in /limepoint/runTime/tmp/deployment
                ::FileUtils.rm_f "/limepoint/runTime/tmp/deployment/gen-app-deployment_#{environment_name}.json"
                ## Add files to Git
                puts 'Adding deployment JSON files to Git'
                %x[ cd #{my_topology_vars['common']['git_repo_path']} && git add "json-files/uploaded/#{environment_name.downcase}" && git commit json-files -m "Updated generated JSON files for #{environment_name.upcase} #{_item_code.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
            end
        end
        #action :nothing
    end

    ruby_block "parseme" do
      block do
        Chef::Log.info("Probe the run state of comp build array ..during parse  #{node.run_state['comp_build_array']}")
       json_data=JSON.parse(::File.open("#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/#{environment_name}_app_deployments.json").read())
        baseplan=json_data['name'].gsub('_','').gsub(' ','').upcase
        planlist=[]
        steplist=[]
        json_data['plans'].each do |p|
          cplan=p['name']
          if cplan.include?('Step') and !cplan.include?('Step 0')
            stepnum=cplan.split('Step')[1].split(' ')[0].split('-')[0].to_i
            puts "#{cplan} is in step #{stepnum}"
            while planlist.length <= stepnum do
              planlist << []
            end
            planlist[stepnum-1] << cplan.split('--')[1].strip
            steplist << cplan.split('--')[1].strip
          end
        end

        puts "All plans:"
        pp planlist

        depshash={}
        # now we form our deps
        # Everything in step 1 depends on itself....
        runningdeps=[]
        planlist[0].each do |p|
          puts "PART 1: #{p}"
          if runningdeps.length > 0
            depshash["_#{p}"]=runningdeps.join(',')
          end
          runningdeps << "_#{p}"
        end

        fulldeps=runningdeps.clone
        # everyhting in step2 is parallel, _except_ documaker, which depends on 'Deploy Day Zero Documaker Cemli'
        planlist[1].each do |p|
          puts "PART 2: #{p}"
          depshash["_#{p}"]=runningdeps.join(',')
          fulldeps << "_#{p}"
        end
        depshash["_*Documaker*"]="_Deploy Documaker"
        depshash["_*Express*"]="_Deploy ODI Batch"
        part4deps=fulldeps.clone

        # everything step3 depends on step 2 and step1
        planlist[2].each do |p|
          puts "PART 3: #{p}"
          puts fulldeps.inspect
          depshash["_#{p}"]=fulldeps.join(',')
          part4deps << "_#{p}"
        end

        planlist[3].each do |p|
          puts "PART 4====>: #{p}"
          puts part4deps.inspect
          depshash["_#{p}"]=part4deps.join(',')
        end

        puts "The Final Deps hash for Step 4 is #{depshash["_Business Config"].inspect}"

        # Component Deployment Injection in to comp_build_array
        comp_step_list = node.run_state['comp_build_array']
        puts "======= Step  List From Comp Compare======="
        puts comp_step_list

        puts "======= Step  List Replaced with Component list======="

        steplist = comp_step_list
        # Add the default ones common for any unit of deployment

        steplist << 'Start up Services'
        steplist << 'Shutdown Services'
        steplist << 'Setup MintDeploy'
        steplist << 'Restart Services'
        steplist << 'Start Documaker Services'
        puts "======= Step  List Final======="
        puts steplist
        puts "======= Deps Hash Final ======="
        puts depshash
        node.run_state['steplist']=steplist
        node.run_state['baseplan']=baseplan
        node.run_state['depshash']=depshash
      end
    end
Chef::Log.info("Finished Parsing ...")
end


if action.downcase == 'deploy'
    ruby_block "Deployment Validation 1 - Check Change" do
        block do
            puts "Checking if there is any component identified for deployment, and throw exception"
            list_for_deployment = node.run_state['comp_build_list_trim']
            puts "Here is the list for deployment  #{list_for_deployment}"

            puts "Here is the list for deployment Size #{list_for_deployment.length}"
            if list_for_deployment.length > 0
                puts "Good to proceed for deployment .."
                Chef.node.run_state['deploy_validation'] = "Success"
            else
                puts "Terminate now  .."
                Chef::Log.error("Terminate deployment as there are no components to deploy ..")
                Chef.node.run_state['deploy_validation'] = "Failed"
                exit(1)
            end
        end
    end
    ruby_block "send email" do
        block do
            puts "Calling deployment notification as the action is to deploy ..."
            baseurl = Chef.node.run_state['baseurl']
            puts "Here is the base url before deploy ... #{baseurl}"
            Chef.node.run_state['deploy_state'] = "initiated"

            msg = "#{environment_name.upcase} -  [#{Chef.node.run_state['manifest']['build_version']}] Deployment Pipeline has started \nPlan URL: : #{baseurl} \n "
            msg << "\n (1) Component Deployment List : #{node.run_state['comp_build_array']} \n"
            sendEmailFn(environment_name.upcase, email_sender,email_list,msg)
        end
    end

    runtime_url=URI.parse(my_topology_vars['deployment']['RUNTIME_IMPORT_URL'])
    runtime_url.scheme ="https"
    runtime_url.port = "443"
    #TBD - move the hard coding of PORT
    mintpress_runtime "run-deployment" do
        protocol runtime_url.scheme
        url runtime_url.host
        port runtime_url.port
        base_path runtime_url.path
        project_list lazy { [node.run_state['baseplan']] }
        dependency_map lazy { node.run_state['depshash'] }
        steps lazy { node.run_state['steplist'] }
        parallel_builds 14
        nonfatal []
        username "#{app_admin_user}"
        password "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}"
     end
end
Chef::Log.info("Completed execution of the Custom Build json file")
