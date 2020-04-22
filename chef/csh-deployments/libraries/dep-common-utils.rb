require 'net/smtp'
require 'tempfile'
require 'net/http'

def pinCookbook(mfrepopath,env_name,kniferbpath)
   puts "============================================================="
   puts "===========Start of Cookbook AutoPinning Block==============="
   puts "============================================================="
   puts "EnvName = #{env_name} -> Manifest Repo Path = #{mfrepopath}"
   environment_name=env_name
   status=%x[cd #{mfrepopath} && git log -1 --stat && git pull --quiet]
   manifestParse=JSON.parse(File.read("#{mfrepopath}/#{environment_name.upcase}/manifest.json"))
   mfCookbookVersion=manifestParse["csh-deployments"]
   puts "#{mfCookbookVersion}"
   repoPath= is_running_on_cloudFn ? "/backup/gitrepos/ocloud-environment-objects" : "/environmint/gitrepos/mp-001_environment_objects"
   puts "Repo Path #{repoPath}"
   status=%x[cd #{repoPath};git pull]
   puts "Status of pull of #{repoPath} is #{status}"
   puts "Content of environment Objects json before updating the JSON"
   envObjFile="#{repoPath}/environment_objects/#{environment_name}.json"
   puts File.read(envObjFile)
   puts "Getting the csh-deployments cookbooks uploaded to server"
   unless (mfCookbookVersion<=>"8.2.3")<0
       cookbooklist=`knife cookbook show csh-deployments -c #{kniferbpath}`
       cookbookexist=cookbooklist.include?(mfCookbookVersion)
       puts "Cookbook uploaded to Chef Server -> #{cookbookexist}"
       puts cookbookexist ? "Proceeding to pin cookbook version #{mfCookbookVersion} to #{environment_name}" : exit
       envObj=JSON.parse(File.read(envObjFile))
       puts "Before Updating cookbook version #{envObj}"
       envObj["cookbook_versions"]["csh-deployments"]="= #{mfCookbookVersion}" if !envObj["cookbook_versions"]["csh-deployments"].eql?(nil)&&!envObj["cookbook_versions"]["csh-deployments"].gsub("=","").strip.eql?(mfCookbookVersion)
       puts "After Updating cookbook version #{envObj}"
       target_temp_env_file="/tmp/#{env_name}_envObj.json"
       File.write(target_temp_env_file,JSON.pretty_generate(envObj))
       status=system("knife environment from file #{target_temp_env_file} -c #{kniferbpath}")
       puts status
       if status
          puts "::::::::Knife cmd Successful ::::::::"
          target_env_file="#{repoPath}/environment_objects/#{environment_name}.json"
          status = system("cp #{target_temp_env_file} #{target_env_file}")
          puts "Copy status result : #{status}"
          result = %x[ cd #{repoPath} && git add "#{target_env_file}" && git commit -am "Updated env objects for #{environment_name.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
          puts "Git Commit result  : #{result}"
          ::FileUtils.rm_f "#{target_temp_env_file}"
       else
          Chef::Log.error( "Knife upload failed ")
          exit(1)
       end
   else
       puts "CSH-Dep Version in Manifest file is less than 8.2.3, Not proceeding with auto pinning"
   end
   puts "============================================================="
   puts "===========End of Cookbook AutoPinning Block==============="
   puts "============================================================="
end


def sendEmailFn(env, from, to, msg)
  Chef::Log.info("Invoke Send Email now")
  begin
    to = to.gsub(/\s+/, "")
    to_array = to.split(',')
    pretty_to = ""

    to_array.each { |x| pretty_to << "<#{x}>," }
    puts "The list of email recipients are : #{pretty_to}"

    message = "From: MintPress DevOps <#{from}>\n"
    message << "To: #{pretty_to}>\n"
    message << "Subject: Deployment  Status for #{env.upcase}\n"
    message << "Date: #{Time.now}\n\n"
    message << "#{env.upcase}  - Deployment  Status\n"
    message << "#{msg}\n"

    if is_running_on_cloudFn

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
        smtp.send_message message, from, to_array
      end
    else
      Net::SMTP.start('appsmtp.thewestpacgroup.com.au', 25) do |smtp|
        smtp.send_message message, from, to_array
        puts "Send email Completed "

      end
    end
    puts " Email - Sent"
  rescue Exception => e
    Chef::Log.info("Sending email failed, but rescued as it is not a critical to break deployment")
    Chef::Log.info("Error Message: #{e.message}")
    Chef::Log.info("Stack Trace: #{e.backtrace.inspect}")
  end
end

#Method to Sync Commit Hash for Deployment Manifest
def syncManifestCommit(env, vars, cdhome)
    begin
        bash "Sync-Dep-Manifest-Commit-Hash" do
            cwd "#{vars['common']['git_repo_path']}/../buildmanifest"
            code <<-EOBASH
            git pull --quiet && newHash=$(git log -n 1  ./#{env}/manifest.json|awk 'FNR == 1 {print $2}')
            if [ -e #{cdhome}/#{env}-manifest-last-commit.log ]; then
                oldHash=`cat #{cdhome}/#{env}-manifest-last-commit.log`
                if [ "$oldHash" != ""  -a  "$oldHash" != "$newHash" ]; then
                    echo $newHash > #{cdhome}/#{env}-manifest-last-commit.log
                fi
            else
                echo $newHash > #{cdhome}/#{env}-manifest-last-commit.log
            fi
            EOBASH
        end
    end
end

#Utility method to create deployment prop
def createDeploymenPropsFn(env, template_source, vars, artifactory_version)
    Chef::Log.info("Invoke deployment property creation method..")
    Chef::Log.info("Get source template from #{template_source}")
    begin

        final_folder="/limepoint/runTime/tmp/deployment/deployment-prop/#{env}"
        unless File.directory?(final_folder)
          FileUtils.mkdir_p(final_folder)
        end
        ::Dir.glob("#{__dir__}/../templates/#{template_source}/*.erb").each do |f|
        bn=::File.basename(f)
        template "#{final_folder}/#{bn.gsub('.erb','')}" do
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

def uploadDeployProp2GitFn(environment_name, tmp_folder, my_topology_vars)
    Chef::Log.info("Invoke uplaod to git from :  #{tmp_folder} to: #{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/deploy-props ")
    ruby_block "upload deploy prop files to git " do
        block do
           if  my_topology_vars['common']['git_commit_on_upload'].downcase == 'true'

                %x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/deploy-props" ]
                ::FileUtils.cp_r "#{tmp_folder}/.", "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/deploy-props", :verbose => true
                # remove the file in /limepoint/runTime/tmp/deployment 
                #::FileUtils.rm_f "tmp_folder"
                ## Add files to Git
                puts 'Adding deployment prop files to Git'
                %x[ cd #{my_topology_vars['common']['git_repo_path']} && git add "json-files/uploaded/#{environment_name.downcase}/deploy-props" && git commit json-files -m "Updated generated deployment property files for #{environment_name.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
            end
        end
    end
end


#Update the response file to GIT , this wil inturn kick off a smoke test automatically
def uploadResponseFile2GitFn(environment_name, response_file, my_topology_vars)
    #Hard Code this for now -  it is tactical, need to move this to a variable
    manifest_git_repo_path = my_topology_vars['deployment']['MANIFEST_GIT_STAGE']
    #TBD Uncommnt this
    #Chef::Log.info("uploadResponseFile2Git - The Topology Vars   is #{my_topology_vars} ");
    Chef::Log.info("uploadResponseFile2Git - manifest_git_repo_path is #{manifest_git_repo_path} ");
    Chef::Log.info("uploadResponseFile2Git - Invoke Upload Response File  to git from :  #{response_file} to: #{manifest_git_repo_path}/RESPONSE_FILES ")

    %x[ mkdir -p "#{manifest_git_repo_path}/RESPONSE_FILES" ]
    #If someone update this file manually , we will get a conflict, so pull  before
    %x[ cd #{manifest_git_repo_path} && git pull --quiet]
    ::FileUtils.cp "#{response_file}", "#{manifest_git_repo_path}/RESPONSE_FILES", :verbose => true
    # remove the file in /limepoint/runTime/tmp/deployment 
    ::FileUtils.rm_f "#{response_file}"
    ## Add files to Git
    puts 'Adding Response  files to Git'
    %x[ cd #{manifest_git_repo_path} && git add "RESPONSE_FILES/#{environment_name}_mintpress_response.json" && git commit RESPONSE_FILES -m "Updated generated Response files for #{environment_name.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
end

def handleResponseFileFn(environment_name,deploy_status, my_topology_vars , stat_vars)
    #TBD revist this var
    response_vars=Chef.node.run_state['response_file']
    manifest_vars=Chef.node.run_state['manifest']
    plan_url=Chef.node.run_state['baseurl']

    resp_env = response_vars['environments']

    #Fetch additional properties for reporting
    enterprise_build_version = manifest_vars['build_version']
    if resp_env.nil?
      #new env - create a new resp
      puts "It is a brand new env for Comp deployment  , initiate hash"
      response_vars = Hash[ "environments" => "#{environment_name}", "deployments" => {} ]
    end
    asset_array=Chef.node.run_state['asset_array']
    asset_array.each do | comp|
          puts "Component Asset Array--------------------------------------------- #{comp}"
          puts "Component Manifest --------------------------------------------- #{manifest_vars['deployments'][comp]}"

          manifest_ext_version = manifest_vars['deployments'][comp]['extension_version']
          manifest_mint_plan = manifest_vars['deployments'][comp]['mint_plan']

          puts "Component Manifest Ext  Version--------------------------------------------- #{manifest_ext_version}"
          puts "Component Manifest Mint Plan --------------------------------------------- #{manifest_mint_plan}"
          if response_vars['deployments'][comp].nil?
             puts "New env [deployments][comp][success_version] is nil , assign null"
             success_version =""
             deploy_status ="NotBuilt"
          else
             success_version = response_vars['deployments'][comp]['success_version']
             puts "Assign previous success version - which is #{success_version}"
             deploy_status =response_vars['deployments'][comp]['status']
             puts "Assign previous success version - which is #{deploy_status}"
          end
          stat_comp_response = stat_vars['statistics'][manifest_mint_plan]
          puts "Here is the  stats #{stat_comp_response}"
          if not stat_comp_response.nil?
              puts "The build state from stats is #{stat_comp_response['buildState']}"
              if (stat_comp_response['buildState'] == "Successful" )
                puts "This component #{comp} was successful using this Orchestration - Lets override with the manifest ext version ::  #{manifest_ext_version} "
                #This is the only place to override the success version
                success_version = manifest_ext_version
              else
                puts "This component #{comp} was NOT successful using this Orchestration "

              end
              deploy_status = stat_comp_response['buildState']
              puts "Irrespective of this component #{comp} status override the real status from the statistics ::   "

          else
            puts "There is no stat data for this comp #{comp}"
          end
          comp_vars = Hash[ comp => {"build_plan" => plan_url, "status" => deploy_status , "build_version" => manifest_ext_version , "success_version" => success_version, "statistics" => stat_comp_response } ]
          response_vars['deployments'].merge!comp_vars

    end
    response_vars['enterprise_build_version'] = enterprise_build_version
    response_vars['deploy_start_time'] = Chef.node.run_state['deploy_start_time']
    response_vars['deploy_end_time'] = Time.now
    elapsed_time = (Time.now - Chef.node.run_state['deploy_start_time']) / 60
    puts "Here is the e2e timings :: #{ response_vars['deploy_start_time']}  to  #{ response_vars['deploy_end_time']}  = #{elapsed_time.round} Mins "

    response_vars['e2e_deployment_duration'] =  elapsed_time.round
    response_vars['mint_project_url'] =  plan_url

    response_file = "/limepoint/runTime/tmp/deployment/response_files/#{environment_name}_mintpress_response.json"
    File.open("#{response_file}","w") do | f |
      f.write(JSON.pretty_generate(response_vars))
    end
    uploadResponseFile2GitFn(environment_name, response_file, my_topology_vars)
    puts "Invoke report URL, as it is not critical to break deployment, running it safely under %x - errors wil be ignored "

    #I want the reporting stuffs loosely coupled until we integrate this to the core of mintpress/console orchestration
    #
    if my_topology_vars['deployment']['REPORT_ENABLED'] == 'true'
      puts "Running Report push for this environment"
      %x[ chef-client -o lp-report::results-ops -l warn -E #{environment_name}  ]
    else
      puts "Report not enabled for this environment"
    end

end

# This function will return true if evaluated on ocloud
def is_running_on_cloudFn()
  if Chef.node['dns'] and Chef.node['dns']['zone']=='wpdev.mintpress.io'
    return true
  else
    return false
  end
end

#This function will wait for any in progress plan which were triggered parallel
#When the chef server
def wait4_inprogress_with_statsFn(plan_key, url, username, password, comp_build_array)

    String creds = username + ":" + password.to_s
    String creds_encoded = Base64.encode64(creds)


    # Get List if Plans in Project
    rest_url = url + "/rest/api/latest/result/" +  plan_key  + ".json?includeAllStates&expand=results.result&max-results=99"
    puts "The Rest API Url #{rest_url}"
    begin
      response_statistics = Hash["statistics" => {}]
      # Invoke REST service
      puts "MintPress Build Plan Build Status for Project Plan [ " + plan_key + " ]"
      started_at = Time.now
      is_building = true
      max_time_out = 10800
      #sleep here for any delay between  deploy and collect
      sleep (5)
      #TBD change this to var  or 2 hours 7200
      combined_list = comp_build_array
      count = 0
      while (is_building and (Time.now - started_at) <= max_time_out)

        puts "--- is building ? - #{is_building} ---"
        is_building = false
        response = RestClient::Request.execute(method: :get, url: rest_url, timeout: 600, open_timeout: 600, headers: {:accept => :json, :content_type => :json, :Authorization => "Basic " + creds_encoded})
        # If successful, Check Response OK
        if (response.code == 200)
          #puts "Response.body: " + response.body.to_s
          response_hash = JSON.parse(response.body.to_s)
          puts "is result a array  #{response_hash['results']['result'].is_a?(Array)}"
          puts "is result a Hash  ..  #{response_hash['results']['result'].is_a?(Hash)}"
          if not response_hash['results']['result'].nil?
            if not response_hash['results']['result'].empty?
              if response_hash['results']['result'].is_a?(Array)
                puts "Lets start probing the result "
                response_hash['results']['result'].each_with_index do |result, index|
                  #puts "Result List at location #{index} =========>"+ result.inspect
                  #shortKey = result['plan']['shortKey']
                  shortName = result['plan']['shortName']
                  puts shortName
                  lifeCycleState = result['lifeCycleState']

                  split_name = shortName.split('--')[1].strip
                  if combined_list.include?(split_name)
                    stats = Hash[split_name => {"lifeCycleState" => lifeCycleState, "buildState" => result['buildState'], "buildStartedTime" => result['buildStartedTime'], "buildCompletedTime" => result['buildCompletedTime'], "buildDurationInSeconds" => result['buildDurationInSeconds']}]
                    response_statistics['statistics'].merge! stats
                    #puts JSON.pretty_generate(response_statistics)
                    if (lifeCycleState == "InProgress")
                      puts "-----Set is-building to true again as  plan  is in  progress-----"
                      is_building = true
                    end

                  else
                    puts "------- This is not to be investigated : #{split_name}------------"
                  end
                end
              else
                puts " Response data ['results']['result'] is not a array - fatal ,, we are not handling it"
                return nil
              end
            else
              puts " Response data ['results']['result'] is empty,, we are not handling it"
              #return nil
            end
          end
        end
        if count <= 10
            sleep(60)
        else
            sleep(300)
        end

        count = count.next
        elapsed_time = (Time.now - started_at) / 60
        puts "Elapsed Time :: #{elapsed_time.round} Minutes "
        puts "What's happening - isbuilding  ? #{is_building}"
        puts JSON.pretty_generate(response_statistics)
      end #while end
      return response_statistics
    rescue => e

      puts "wait4_inprogress_with_stats() Exception: " + e.inspect
      if e.response.code == 500
        puts "response.code == 500. Assuming false." + e.inspect
        return nil
      else
        puts "Unable to find buildState for Project Plan Key ..."
        #Chef::Log.info("Unable to find buildState for Project Plan Key [ " + plan_key + " ] - assuming built!")
        puts "returning nil"
        return nil
      end
    end

  end


  def isPlanExists(plan_key, dataBag)
    app_admin_user = dataBag['deployment']['RUNTIME_APP_ADMIN_USER']
    puts "Admin User::  #{app_admin_user}"
    baseplan=plan_key.gsub('_','').gsub(' ','').upcase
    puts "Base Plan   : #{baseplan}"
    base_url = "#{dataBag['deployment']['RUNTIME_IMPORT_URL']}/rest/api/latest/project/#{baseplan}.json?showEmpty=true"
    puts "Base Url ::  #{base_url}"
    begin

        result=RestClient::Request.execute(method: :get, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}", url: "#{base_url}",  headers: {'Content-Type' => 'application/json' })

    rescue RestClient::ExceptionWithResponse => e
         puts("Exception unable to find project on  Mintpress Runtime")
         puts("Error Message: #{e.message}")
         puts("Stack Trace: #{e.backtrace.inspect}")
         if e.message.include?"500"
           puts "There is internal error, there should be a junk project already.Return true, this should help to recover from envs having the duplicated projects already"
           return true
         else
           puts "404 or  any other codes, we will consider that the plan does not exists. Return false"
           return false
         end
    end

    puts "Rest API , Project search Result ::  #{result}"
    result.strip
    if result.include? "\"expand\":\"plans\""
        puts "Project Exists on the Runtime, return true"
        return true
    else
        puts("Failed to find project on  Mintpress Runtime, return false")
        return false
    end

  end
