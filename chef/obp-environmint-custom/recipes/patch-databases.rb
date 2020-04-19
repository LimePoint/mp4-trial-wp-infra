# Author        : Uday Bulusu
# Description   : Recipe to patch the databases with a given patch (#{patch2apply})
#

require 'tempfile'
require 'base64'


# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

if is_running_on_cloud

	environment_name = node.chef_environment.downcase

	my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
    db_version = my_topology_vars['common'].key?('database_version') ? my_topology_vars['common']['database_version'] : '12.1.0.2'
    patch2apply = db_version == '12.1.0.2' ? 'p29158680_12102171017ProactiveBP_Linux-x86-64' : 'p29158680_12201181016DBOCT2018RU_Linux-x86-64'

    ruby_block "stop-db-services" do
        block do
            run_context.include_recipe "obp-environmint-custom::stop-db-services"
        end
        action :nothing
    end

    ruby_block "startup-db-services" do
        block do
            run_context.include_recipe "obp-environmint-custom::start-db-services"
        end
        action :nothing
    end

    oracle_listener 'stop-listener' do
      listener_name node['oracle']['database']['listenerList'][0]['name']
      listener_port node['oracle']['database']['listenerList'][0]['port']
      oracle_home node['oracle']['database']['listenerList'][0]['oracle_home']
      user 'oracle'
      group 'oinstall'
      action :stop
      notifies :run, 'ruby_block[stop-db-services]', :before
    end

    oracle_patch "prereq-for-p29158680" do
      patch_name 'p26635880_121020_Linux-x86-64'
      patch_aru '26635880'
      oracle_home node['oracle']['database']['databaseList'][0]['oracle_home']
      software_stage "/oracle/stage/rdbms/Linux-x86_64/#{db_version}/database/patches"
      inventory_location node['oracle']['oracle_inventory']
      user 'oracle'
      group 'oinstall'
      shutdown_instances false
      action :nothing
      only_if { db_version == '12.1.0.2' }
    end

    oracle_patch "prereq-for-p29158680" do
      patch_name 'p28662603_122010_Linux-x86-64'
      patch_aru '28662603'
      oracle_home node['oracle']['database']['databaseList'][0]['oracle_home']
      software_stage "/oracle/stage/rdbms/Linux-x86_64/#{db_version}/database/patches"
      inventory_location node['oracle']['oracle_inventory']
      user 'oracle'
      group 'oinstall'
      shutdown_instances false
      action :nothing
      only_if { db_version == '12.2.0.1' }
    end

    oracle_patch "p29158680-for-JSON-TAB-QUERY" do
      patch_name patch2apply
      patch_aru '29158680'
      oracle_home node['oracle']['database']['databaseList'][0]['oracle_home']
      software_stage "/oracle/stage/rdbms/Linux-x86_64/#{db_version}/database/patches"
      inventory_location node['oracle']['oracle_inventory']
      user 'oracle'
      group 'oinstall'
      shutdown_instances false
      action :apply
      notifies :apply, 'oracle_patch[prereq-for-p29158680]', :before
    end

    oracle_listener 'start-listener' do
      listener_name node['oracle']['database']['listenerList'][0]['name']
      listener_port node['oracle']['database']['listenerList'][0]['port']
      oracle_home node['oracle']['database']['listenerList'][0]['oracle_home']
      user 'oracle'
      group 'oinstall'
      wait_for_services false
      action :start
      notifies :run, 'ruby_block[startup-db-services]', :before
    end
end
