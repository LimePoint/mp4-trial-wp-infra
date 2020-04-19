# Author        : Uday Bulusu
# Description   : Recipe to stop all the LISA services
#

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

lisa_home="/oracle/app/DevTest"
svc_list = %w[ VirtualServiceEnvironmentService PortalService RegistryService ]

if is_running_on_cloud
    if node['fqdn'].start_with?('obpclisa')
        svc_list.each do |svc|
            execute "Stop-#{svc}" do
                command "#{lisa_home}/bin/#{svc} stop"
                only_if "ps -ef|grep #{svc}|grep -v grep"
            end
        end

        execute "Waiting for 60 secs" do
            command "sleep 60"
        end

        svc_list.each do |svc|
            execute "killing-stubborn-#{svc}" do
                command "PID=`ps -ef|grep #{svc}|grep -v grep|awk '{print $2}'`; kill -9 $PID"
                only_if "ps -ef|grep #{svc}|grep -v grep"
            end
        end
    else
        Chef::Log.info("This is NOT a LISA host. Nothing to do here!!")
    end
end
