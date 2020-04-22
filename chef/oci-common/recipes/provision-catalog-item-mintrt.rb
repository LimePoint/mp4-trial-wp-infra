# The sole reason for this recipe to exist is to bootstrap this instance of MintPress Runtime with the MintPRess Alpha/Omega instance
# This recipe is not used to build the MintPRess itself

if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = ''
end

host_opts = node.run_state['MINTRT']['properties']['mintrt']
host_opts[:environment_name] = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
p_id = node.run_state['orchestration_metadata']['launchDetails']['providersToServiceCatalogItems'][0]['providerCode']
attrs = {
	"environmint": { "orchestration_key": "#{node.run_state['orchestration_metadata']['uuid']}" },
	"provisioning_env": "environmint-provisioning",
    "provider_id": p_id
}
host_opts[:node_attributes] = attrs
# Transform hash keys to symbols; no specific reason just personal preference
host_opts.transform_keys!(&:to_sym)
Chef::Log.info("Input Received: #{host_opts}")

# Force the inputs for DNS coz we know better.
host_opts[:instance_type] = 'VM.Standard.E2.8'
host_opts[:operating_system] = 'Oracle Linux'
host_opts[:operating_system_version] = 7

bds = [
  {name: 'opt', mount_point: '/opt', size_mb: 50 * 1024},
  {name: 'var2', mount_point: '/var/opt', size_mb: 50 * 1024},
  {name: 'cache', mount_point: '/cache', size_mb: 50 * 1024},
  {name: 'limepoint', mount_point: '/limepoint', size_mb: 100 * 1024},
  {name: 'backup', mount_point: '/backup', size_mb: 100 * 1024}
]
host_opts[:block_devices] = bds
host_opts[:disable_selinux] = true
host_opts[:run_list] = ['oci-bootstrap::default']
oci_host = MintOCIHost.new(host_opts)

case 
  when mp_action == 'provision'
    # provision
    Chef::Log.info("Provision action detected. Creating the VM")
    oci_host.create
  when mp_action == 'destroy'
    # destroy
    Chef::Log.info("Destroy action detected. Deleting the VM")
    Chef::Log.info("But I am MintPress, I cannot be deleted by click of a button.")
    Chef::Log.info("If you know what you are doing, fix this in the code and rerun.")
    raise
    # If you really need to destroy, uncomment the following line and remove the raise from above 
    #oci_host.destroy
  else
    # Do nothing
    Chef::Log.info("No action specified. Nothing to do")
    return
end 

return unless mp_action == 'provision'

