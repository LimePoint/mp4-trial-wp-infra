#====================================================================================================================================
# Recipe Name       :: notify-status
# Author            :: Uday B
# Description       :: Sends notifications to intended recipients(audience) for all actions except 'generatevars' and 'uploadonly'
#                      triggered on the OBPALL catalog instance
#====================================================================================================================================

require 'json'
require 'tempfile'
require 'base64'
require 'net/ssh'
require 'net/ping'
# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

def uploadStatus2Git(env_name, vars)
  Chef::Log.info("Invoke upload of new/updated build status to git ")
  ruby_block "upload new/updated files to git " do
    block do
        %x[ mkdir -p "#{vars['common']['git_repo_path']}/../buildmanifest/#{env_name.upcase}" ]
        ::FileUtils.cp_r Dir.glob("/tmp/#{env_name}/*_status.json"), "#{vars['common']['git_repo_path']}/../buildmanifest/#{env_name.upcase}/", :verbose => true
        ## Add files to Git
        puts 'Adding Build Status '
        %x[ cd "#{vars['common']['git_repo_path']}/../buildmanifest" && git pull --quiet && git add -A && git commit -am "Updated/Added Build Status files for #{env_name.upcase}"; git log -1 --stat && git pull --quiet && git push origin master --quiet]
     end
  end
end

_item_code='OBPALL'
my_topology_vars = topology_vars(_item_code)
environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase

if node.run_state.key?('mintpress_action')
    mp_action = node.run_state['mintpress_action']
else
    mp_action = 'uploadonly'
end
sender = 'wpocloud@limepoint.com'
recipients = ['cshwp@limepoint.com']
#bpad_devops = ['DL.BPAD.DevOps@westpac.com.au']
bpad_devops_env = (1..31).to_a.map{|e| "bpd"+e.to_s}
if bpad_devops_env.include?(environment_name)
#    recipients += bpad_devops
end

ruby_block "Notify Others" do
    block do
        unless File.directory?("/tmp/#{environment_name}")
            FileUtils.mkdir_p("/tmp/#{environment_name}")
        end
        if mp_action=='destroy'
            destroy_dt =  Date.today
            Chef::Log.info("Destroy Date is => '#{destroy_dt}'. Save the date for Future reference!!!")
            destroy_data = { "destroy_date" => "#{destroy_dt}" }
            File.open("/tmp/#{environment_name}/destroy_status.json", "w+") do |f|
                f.write(JSON.generate(destroy_data))
            end
        else
            destroy_dt = 'Yet to be destroyed'
        end

        if mp_action=='provision'
            build_dt = Date.today
            Chef::Log.info("Build Date is => '#{build_dt}'. Save the date for Future reference!!!")
            build_data = { "build_date" => "#{build_dt}" }
            File.open("/tmp/#{environment_name}/build_status.json", "w+") do |f|
                f.write(JSON.generate(build_data))
            end
        end

        mailmsg = "From: MintPress DevOps <#{sender}>\n"
        mailmsg << "To: <#{recipients}> \n"

        if mp_action=='handoverReport'
            handover_dt = Date.today
            rebuild_due_dt = handover_dt + 90
            handover_data = [{ "handover_date" => "#{handover_dt}" }, { "rebuild_due_date" => "#{rebuild_due_dt}" }]
            File.open("/tmp/#{environment_name}/handover_status.json", "w+") do |f|
                f.write(JSON.generate(handover_data))
            end
            mailmsg << "Subject: Provision/Rebuild of #{environment_name.upcase} Completed! Environment is ready for handover.\n"
            mailmsg << "Date: #{Time.now}\n\n"
            mailmsg << "Environment Handed over on => #{handover_dt.strftime('%d-%b-%Y')}\n"
            mailmsg << "Environment Rebuild due on => #{rebuild_due_dt.strftime('%d-%b-%Y')}\n"
        else
            mailmsg << "Subject: Status Update for #{environment_name.upcase} - #{mp_action.upcase} : In progress.\n"
            mailmsg << "Date: #{Time.now}\n\n"
            mailmsg << "Executing the action: #{mp_action.upcase}\nFor Environment: #{environment_name.upcase}\n"
        end
        sendEmail(environment_name, sender, recipients, mailmsg, notify_others:1)
        Chef::Log.info("Notification Sent")
    end
    not_if { ['generatevars','uploadonly'].include?(mp_action) }
end
uploadStatus2Git(environment_name, my_topology_vars)
