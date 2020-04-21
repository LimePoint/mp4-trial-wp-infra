require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OCHAPP'
return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####
#
Chef::Log.info("ENV: #{environment_name}")

global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge!(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)
asset_vars = my_topology_vars[_item_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']

#### Add asset specific code here ####

if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = ''
end

providerCode = lookup_catalogitem_providerCode(_item_code)
host_opts = {}
host_opts[:hostname] = "obpcss#{environment_name}ap.wpdev.mintpress.io"
host_opts[:environment_name] = environment_name
host_opts[:instance_type] = 'VM.Standard.E2.4'
host_opts[:operating_system] = 'Oracle Linux'
host_opts[:operating_system_version] = 6
host_opts[:disk_size] = 50
attrs = {
  "environmint": { "orchestration_key": "#{node.run_state['orchestration_metadata']['uuid']}" },
  "provisioning_env": "environmint-provisioning",
  "provider_id": providerCode
}
host_opts[:node_attributes] = attrs
host_opts[:run_list] = ['oci-bootstrap::default']
host_opts[:create_cnames] = true

# The app node has no friendly names
host_opts[:create_friendly_names] = false
# Transform hash keys to symbols; no specific reason just personal preference
host_opts.transform_keys!(&:to_sym)
oci_host = MintOCIHost.new(host_opts)

case 
  when mp_action == 'provision'
    # provision
    Chef::Log.info("Provision action detected. Creating the VM")
    oci_host.create
  when mp_action == 'destroy'
    # destroy
    Chef::Log.info("Destroy action detected. Deleting the VM")
    oci_host.destroy
    return
  else
    # Do nothing
    Chef::Log.info("No action specified. Nothing to do")
    return
end 
