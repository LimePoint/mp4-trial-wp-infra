require 'tempfile'
require 'base64'
require "net/http"
require "uri"


# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='DCMSDEP'
return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))

global_properties = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.merge(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)
my_topology_vars.merge!(Hash({'environment_name' => environment_code}))
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))
my_topology_vars = my_dep_vars.merge(my_topology_vars)

if node.run_state.key?('mintpress_action')
    action = node.run_state['mintpress_action']
else
    action = 'uploadonly'
end
puts "The Current Action :: #{action}"

ssh_key_path = my_topology_vars['deployment']['SSH_KEY']
if ssh_key_path.nil?
  # TBD remove this .. but we may need a default email
  ssh_key_string = ' '
else
  ssh_key_string = "-i " + ssh_key_path
end

#Send Email at the begining of the Orchestration
email_list = my_topology_vars['dcms']['notify_recipients']
puts "Notification Email for this Env is : #{email_list} "
if email_list.nil?
    email_list = 'harsha.gurram@westpac.com.au'
end
=begin
#Send Email when the recipe is  completed successfully
Chef.event_handler do
 on :run_completed do
    baseurl = Chef.node.run_state['baseurl']
    if action.downcase == 'deploy' or action.downcase == 'uploadonly'
        msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}]  Succeeded \n Plan URL: : #{baseurl} \n"
        sendEmail(environment_name, 'harsha.gurram@westpac.com.au',email_list,msg)
        puts " Response file created already just commit  after email "
        response_file = "/environmint/tmp/dcms/reponse_files/#{environment_name}_mintpress_response.json"
        uploadResponseFile2Git(environment_name, response_file)
    end
 end
end

#Send Email when the recipe failed
Chef.event_handler do
 on :run_failed do
   Chef::Log.info("From the event failure of the recipe==>")
   baseurl = Chef.node.run_state['baseurl']
   msg = "#{environment_name.upcase} - Deployment Action[#{action.upcase}]  Failed \n Plan URL: : #{baseurl} \n"
   msg << "\n There may be some plans still running on MintPress Runtime. \n Trigger new deployment only after manually stopping them or wait for them to complete.\n"
   sendEmail(environment_name.upcase, 'harsha.gurram@westpac.com.au',email_list,msg)
 end
end

#TBD change this to deploy only later, no need for notification on upload
if action.downcase == 'deploy' or action.downcase == 'uploadonly'
    msg = "#{environment_name.upcase} - Deployment  Action[#{action.upcase}] Initiated \n"
    sendEmail(environment_name, 'harsha.gurram@westpac.com.au',email_list,msg)

end

=end

password_vault_name = my_topology_vars['common']['password_vault_name']

log "Creating Deployment json .."

password_from_vault = PasswordVault.get_password('mintpress','runtime_app_admin','password')
PasswordVault.put_password('mintpress','runtime_app_admin','password', password_from_vault)
app_admin_user = my_topology_vars['deployment']['RUNTIME_APP_ADMIN_USER']
puts app_admin_user


if action.downcase == 'deploy' or action.downcase == 'uploadonly'

# 1. Create Deployment json from template    

    template 'DCMS deployment template' do
      source "dcms/dcms_deploy_plan.json.erb"
      path "/environmint/tmp/dcms/#{environment_name}_dcms_deploy_plan.json"
      variables(
            variables(
                :dataBag => my_topology_vars,
                :environment_name => environment_name,
                :ssh_key_string => ssh_key_string
            )
        )
      mode '0644'
    end

    log "Completed Creating Deployment JSON"
# 2. Upload to RT

    ruby_block "Upload to Runtime" do
        block do
          payload_data=::File.open("/environmint/tmp/dcms/#{environment_name}_dcms_deploy_plan.json").read()
          json_data=JSON.parse(payload_data)
          baseplan=json_data['name'].gsub('_','').gsub(' ','').upcase
          baseurl= "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/browse/#{baseplan}"
          result=RestClient::Request.execute(method: :post, user: "#{app_admin_user}", password: "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}", url: "#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}/rest/envmint/1.0/importProject", payload: payload_data, headers: {'Content-Type' => 'application/json' })
          puts "Uploaded with #{result}"
          if result.include? "Successfully imported Bamboo project"
             puts "Import to Runtime Successful"
             puts baseurl
             node.run_state['baseurl']=baseurl
             Chef::Log.info("Here is the base url after import  ... #{node.run_state['baseurl']}")
             #Below update console url needs to be fixed
             #update_console_urls_for_catalogitem(node['environmint']['orchestration']['key'], _item_code.upcase, baseurl)
          else
            log "Failed to import json to Mintpress Runtime"
            exit(1)
          end
        end
    end



    log "Completed Upload Only Stage"
=begin
# 3. Upload to GIT
    ruby_block "upload files to git " do
        block do

            if  my_topology_vars['common']['git_commit_on_upload'].downcase == 'true'

                %x[ mkdir -p "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}" ]

                ::FileUtils.cp "/environmint/tmp/dcms/#{environment_name}_dcms_deploy_plan.json", "#{my_topology_vars['common']['git_repo_path']}/json-files/uploaded/#{environment_name.downcase}/#{environment_name}_dcms_deploy_plan.json", :verbose => true

                # remove the file in /environmint/tmp/dcms
                ::FileUtils.rm_f "/environmint/tmp/dcms/#{environment_name}_dcms_deploy_plan.json"
                ## Add files to Git
                puts 'Adding deployment JSON files to Git'
                %x[ cd #{my_topology_vars['common']['git_repo_path']} && git add "json-files/uploaded/#{environment_name.downcase}" && git commit json-files -m "Updated generated JSON files for #{environment_name.upcase} #{_item_code.upcase}" && git log -1 --stat && git pull --quiet && git push --quiet]
            end
        end
        #action :nothing
    end
    log "Committed to GIT"
=end
end

if action.downcase == 'deploy'
  runtime_url=URI.parse("#{my_topology_vars['deployment']['RUNTIME_IMPORT_URL']}")
  ruby_block "parseme" do
    block do
      puts "RT Instance to invoke #{runtime_url}"
      json_data=JSON.parse(::File.open("/environmint/tmp/dcms/#{environment_name}_dcms_deploy_plan.json").read())
      baseplan=json_data['name'].gsub('_','').gsub(' ','').upcase
      steplist=[]
      steplist << 'DCMS DEPLOYMENT'
      node.run_state['baseplan']=baseplan
      node.run_state['steplist']=steplist
      puts "PROJECT PLAN IS - #{node.run_state['baseplan']}"
      puts "STEPS ARE #{node.run_state['steplist']}"
    end
  end

  mintpress_runtime "run-deployment" do
    protocol runtime_url.scheme
    url runtime_url.host
    port runtime_url.port
    base_path runtime_url.path
    project_list lazy { [node.run_state['baseplan']] }
    steps lazy { node.run_state['steplist'] }
    parallel_builds 10
    username "#{app_admin_user}"
    password "#{Mint::AesEncryption.decrypt(PasswordVault.get_password('mintpress',"#{app_admin_user}",'password'))}"
  end
end

log "Completed execution of the Custom Build json file"

