# Author        : Uday Bulusu
# Description   : Recipe to start all the database listeners
#

require 'tempfile'
require 'base64'


# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

if is_running_on_cloud
    node['oracle']['database']['listenerList'].each do |lsnr|
        oracle_listener "startup-#{lsnr['name']}" do
            listener_name lsnr['name']
            listener_port lsnr['port']
            oracle_home lsnr['oracle_home']
            user 'oracle'
            group 'oinstall'
            wait_for_services false
            action :start
        end
    end
end
