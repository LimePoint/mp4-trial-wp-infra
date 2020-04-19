# Author        : Uday Bulusu
# Description   : Recipe to start all the LISA services
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
        ruby_block "stop-lisa-services" do
            only_if "ps -ef|egrep -e \"#{svc_list.join('|')}\"|grep -v grep"
            block do
                run_context.include_recipe "obp-environmint-custom::lisa-svc-stop"
            end
        end

        case
        when node['fqdn'].include?('lisa1')
            svc_list.each do |svc|
                execute "Start-#{svc}" do
                    command "#{lisa_home}/bin/#{svc} start"
                end
            end
        when node['fqdn'].include?('lisa2')
            execute "Start-#{svc_list[0]}" do
                command "#{lisa_home}/bin/#{svc_list[0]} start"
            end
        end

    else
        Chef::Log.info("This is NOT a LISA host. Nothing to do here!!")
    end

end
