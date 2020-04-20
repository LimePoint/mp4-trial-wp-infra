require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OBPOID'
##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####

my_topology_vars = topology_vars(_item_code)

#### Add asset specific code here ####
custom_ldif_location = "#{my_topology_vars['common']['git_repo_path']}/custom/csh/ocloud_user_config"
stage_location = "/oracle/stage/oid_custom_ldif/ocloud_user_config"

directory stage_location do
  mode 0755
  recursive true
  action :create
end

bash "Staging custom LDIF files" do
    code <<-EOF
    mkdir -p #{custom_ldif_location}
    cp -ur #{custom_ldif_location}/* #{stage_location}
    EOF
end
