# Author        : Uday Bulusu
# Description   : Recipe to start all the database services
#

require 'tempfile'
require 'base64'


# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

if is_running_on_cloud
    node['oracle']['database']['databaseList'].each do |db|
        oracle_service "startup-#{db['name']}" do
            oracle_home db['oracle_home']
            database_name db['version'] == "12.2.0.1" ? db['name'].gsub('_','') : db['name'].gsub('_','')[0..7]
            user 'oracle'
            group 'oinstall'
            action :startup
        end
    end

    ruby_block "startup-db-listener" do
        block do
            run_context.include_recipe "obp-environmint-custom::start-db-listener"
        end
    end
end
