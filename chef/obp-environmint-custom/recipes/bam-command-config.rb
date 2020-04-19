# Author: Romil Bhagat

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

# This recipe populates the required environment specific values in the BAMCommandConfig.xml file

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']
release_version = my_topology_vars['obpsoa']['release_version']

template "Configuring bamcommand" do
    source "fmw/BAMCommandConfig.xml.erb"
    path "/oracle/app/binaries/obpsoa/fmw/soa/bam/bin/BAMCommandConfig.xml"
    variables (
        variables(
        :tvars => my_topology_vars
        )
    )
    mode '0704'
    user 'oracle'
    group 'oinstall'
end
