require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

#
# Recipe:: install-contrast-agent
# Author: Harsha Gurram
#
environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

if my_topology_vars['common']['enable_contrastagent'] == 'false' then
	Chef::Log.info("This environment is not supported for Contrast. Doing Nothing.")
	return
end

if !(node.automatic['filesystem2']['by_mountpoint'].key?("/oracle/app/binaries") and node.automatic['filesystem2']['by_mountpoint']['/oracle/app/binaries']['mount_options'].include? "rw") then
	Chef::Log.info("This is a passive node, skipping contrast jar copy")
	return
end
username='oracle'
groupname='oinstall'
install_dir= '/oracle/app/binaries/contrast_agent'
contrast_agent_source_file = 'https://artifactory.srv.westpac.com.au/artifactory/MP-001_CSH-Release/au/com/westpac/csh/contrast/1.0.0/contrast-1.0.0.jar'

directory "#{install_dir}" do
	owner "#{username}"
	group "#{groupname}"
	mode 0755
	recursive true
	action :create
end
# Download the contrast agent jar from Artifactory.
remote_file "#{install_dir}/contrast.jar" do
	source "#{contrast_agent_source_file}"
	owner "#{username}"
	group "#{groupname}"
	mode '0755'
	action :create
	not_if { ::File.exist?("#{install_dir}/contrast.jar") }
end
