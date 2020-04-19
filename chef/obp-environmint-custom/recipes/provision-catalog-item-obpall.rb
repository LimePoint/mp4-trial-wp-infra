require 'tempfile'
require 'base64'
require 'fileutils'
require 'net/ping'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPALL'
return unless node.run_state[_item_code]

if is_running_on_cloud
	include_recipe "obp-environmint-custom::provision-catalog-item-obpall-ocloud"
else
	include_recipe "obp-environmint-custom::provision-catalog-item-obpall-onprem"
end
