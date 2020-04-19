#====================================================================================================================================
# Recipe Name       :: notify-expiry
# Author            :: Uday B
# Description       :: Sends notifications to intended recipients(audience) informing an environment's rebuild due date.
#====================================================================================================================================

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

bm_path="/oracle/gitrepos/buildmanifest"
sender = 'wpocloud@limepoint.com'
recipients = ['cshwp@limepoint.com','uday.bulusu@westpac.com.au']
#bpad_devops = ['DL.BPAD.DevOps@westpac.com.au']
stale_envs = []

Dir.glob("#{bm_path}/BPD*/handover_status.json").each do |f|
  env_name = File.basename(File.dirname(f))
  data=JSON.parse(File.read(f)).find {|x| x['rebuild_due_date']}['rebuild_due_date']
  due_date= Date.parse(data)

  if due_date <= Date.today + 7
    if (due_date - Date.today) <= 0
        stale_envs << "Environment #{env_name} was due for rebuild on \t=> #{due_date.strftime('%d-%b-%Y')}"
    else
        stale_envs << "Environment #{env_name} is due for rebuild on \t=> #{due_date.strftime('%d-%b-%Y')}"
    end
  end

end

ruby_block "Notify Expiry" do
    block do
        mailmsg = "From: MintPress DevOps <#{sender}>\n"
        mailmsg << "To: <#{recipients}> \n"
        mailmsg << "Subject: O-Cloud Environments Requiring Rebuild or Soon-to-be Due for a Rebuild.\n"
        mailmsg << "Date: #{Time.now}\n\n"
        mailmsg << "List of Stale Environments:\n"
        mailmsg << "============================\n\n"
        stale_envs.each { |e| mailmsg << "#{e}\n" }

        sendEmail('O-Cloud Environments', sender, recipients, mailmsg, notify_others:1)
        Chef::Log.info("Notification was sent to >> #{recipients}")
    end
    not_if { stale_envs.empty? }
end
