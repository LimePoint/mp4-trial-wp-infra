if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = ''
end

host_opts = node.run_state['WPDNS']['properties']['wpdns']
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
host_opts[:instance_type] = 'VM.Standard.E2.2'
host_opts[:operating_system] = 'Oracle Linux'
host_opts[:operating_system_version] = 7

# for LDAP we need /opt
bds = [{name: 'opt', mount_point: '/opt', size_mb: 50 * 1024}]
host_opts[:block_devices] = bds
host_opts[:disable_selinux] = true
host_opts[:run_list] = ['oci-common::default']
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

return unless mp_action == 'provision'

sec_group = MintPress::InfrastructureOci::OCINetworkSecurityGroup.new(
  display_name: "dns_god",
  vcn_id: oci_host.configs['oci_platform']['vcn_id'])

sec_list = MintPress::InfrastructureOci::OCISecurityGroupRule.new(
  network_security_group: sec_group,
  description: "rule to allow all external access to be used for installation. this rule is temporary and should not exist post install.",
  destination_type: "CIDR_BLOCK",
  destination: "0.0.0.0/0",
  direction: "EGRESS",
  protocol: 'all')

dns_host = oci_host.host_obj
configs = oci_host.configs

# Define the sec group to allow downloading from all sources temporarily
# Find if LDAP is installed
if !dns_host.transport.File.exist?('/etc/pdns/pdns.conf')
  Chef::Log.info 'PowerDNS Binaries dont exists. Downloading and installing...'

  # Temporarily allow the host to talk to the internet
  sec_group.create
  sec_list.create
  dns_host = oci_host.host_obj

  dns_host.add_network_security_group_by_display_name('dns_god')
  dns_host.update
  dns_host.transport.putfile("/backup/dns/setup_powerdns.sh", "/tmp/setup_powerdns.sh")
  #dns_host.transport.putfile("/backup/dns/remove_powerdns.sh", "/tmp/remove_powerdns.sh")
  dns_host.transport.putfile("/backup/dns/powerdns_gsql.sql", "/tmp/powerdns_gsql.sql")

  dns_admin_password = configs['powerdns_platform']['dns_admin_password']
  dns_api_key = configs['powerdns_platform']['dns_api_key']
  dns_web_password = configs['powerdns_platform']['dns_web_password']
  dns_forward_zones = configs['powerdns_platform']['dns_forward_zones']
  
  install_cmd = "cd /tmp && sh /tmp/setup_powerdns.sh -d #{dns_admin_password} -a #{dns_api_key} -w #{dns_web_password} -p 80 -f '0.0.0.0/0' -z '#{dns_forward_zones}' && rm -f /tmp/setup_powerdns.sh /tmp/powerdns_gsql.sh"
  raise 'Could not install and configure DNS' if dns_host.transport.execute("#{install_cmd}").exit_status > 0 

  # Remove the mariadb repo
  dns_host.transport.execute("rm -f /etc/yum.repos.d/mariadb.repo")

  Chef::Log.info ('Creating the default zone')
  require 'mintpress-dns-powerdns'
  mydns = MintPress::DNS::PowerDNS.new(webserver_host: dns_host.primary_ip, webserver_port: 80, api_key: dns_api_key)
  zone_details = { name: 'wpdev.mintpress.io', kind: 'Native', dnssec: false, nameservers: ['dns-alpha.wpdev.mintpress.io', 'dns-omega.wpdev.mintpress.io'] }  
  mydns.zone_create(zone_details)

  # Remove the temp sec group
  dns_host.remove_network_security_group_by_display_name('dns_god')
  dns_host.update
  sec_group.remove
else
  Chef::Log.info 'DNS Already exists. No Action'
end

