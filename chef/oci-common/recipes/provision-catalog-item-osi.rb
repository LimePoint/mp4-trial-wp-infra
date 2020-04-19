if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = ''
end

host_opts = node.run_state['OSI']['properties']['osi']
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
  else
    # Do nothing
end 
