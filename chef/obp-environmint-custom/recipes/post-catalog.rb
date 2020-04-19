# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

if is_running_on_cloud
	
	if node.run_state['mintpress_action']=='startup' and node.run_state['machine_queue'] and node.run_state['machine_queue'].length > 0
		Chef::Log.info("knife ssh 'chef_environment:#{environment_code}' -i ~/.ssh/wpac-ocloud -a ipaddress -t 2 --no-host-key-verify -x opc 'sudo chef-client -l info -o os-common::update-hostsfile'")
		bash "chef-everyone" do
			code <<-EOH
				/bin/knife ssh 'chef_environment:#{environment_code}' -i ~/.ssh/wpac-ocloud -a ipaddress -t 2 --no-host-key-verify -x opc 'sudo chef-client -l info -o os-common::update-hostsfile'
			EOH
		end
	end
end
