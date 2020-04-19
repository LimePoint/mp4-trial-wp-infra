if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = ''
end

host_opts = node.run_state['WPLDAP']['properties']['wpldap']
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

# Force the inputs for LDAP  coz we know better.
host_opts[:instance_type] = 'VM.Standard.E2.2'
host_opts[:operating_system] = 'Oracle Linux'
host_opts[:operating_system_version] = 7

# for LDAP we need /opt
bds = [{name: 'opt', mount_point: '/opt', size_mb: 50 * 1024}]
host_opts[:block_devices] = bds
host_opts[:disable_selinux] = true
host_opts[:run_list] = ['oci-bootstrap::default', 'oci-bootstrap::ldap-server-configs']
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
  display_name: "ldap_god",
  vcn_id: oci_host.configs['oci_platform']['vcn_id'])

sec_list = MintPress::InfrastructureOci::OCISecurityGroupRule.new(
  network_security_group: sec_group,
  description: "rule to allow all external access to be used for installation. this rule is temporary and should not exist post install.",
  destination_type: "CIDR_BLOCK",
  destination: "0.0.0.0/0",
  direction: "EGRESS",
  protocol: 'all')

ldap_host = oci_host.host_obj

# Define the sec group to allow downloading from all sources temporarily
# Find if LDAP is installed
if !ldap_host.transport.File.exist?('/opt/openldap-current/etc/openldap/slapd.ldif')
  Chef::Log.info 'LDAP Binaries dont exists. Downloading and installing...'

  # Temporarily allow the host to talk to the internet
  sec_group.create
  sec_list.create
  ldap_host = oci_host.host_obj

  ldap_host.add_network_security_group_by_display_name('ldap_god')
  ldap_host.update
  ldap_host.transport.putfile("/backup/ldap/ldap_install_configure.sh", "/tmp/ldap_install_configure.sh")
  raise 'Could not install and configure LDAP' if ldap_host.transport.execute("sh /tmp/ldap_install_configure.sh").exit_status > 0 

  # Transfer certs
  ldap_host.transport.execute("mkdir -p /opt/custom_certs")
  ldap_host.transport.putfile("/backup/certs/server_cert.pem", "/opt/custom_certs/server_cert.pem")
  ldap_host.transport.putfile("/backup/certs/server_private_key.pem", "/opt/custom_certs/server_private_key.pem")
  ldap_host.transport.putfile("/backup/certs/certificate_chain.pem", "/opt/custom_certs/certificate_chain.pem")

  # Transfer the systemctl service
  ldap_host.transport.putfile("/backup/ldap/ldap.service", "/etc/systemd/system/ldap.service")
  ldap_host.transport.putfile("/backup/ldap/ldap.environment", "/etc/sysconfig/slapd-current")

  # Transfer the sudo.ldif
  ldap_host.transport.putfile("/backup/ldap/sudo.ldif", "/opt/openldap-current/etc/openldap/schema/sudo.ldif")

  # Transfer the slapd.ldif
  ldap_host.transport.putfile("/backup/ldap/ldap_slapd.ldif", "/opt/openldap-current/etc/openldap/slapd.ldif")

  # Load the DB
  ldap_host.transport.execute("echo 'export PATH=/opt/openldap-current/bin:/opt/openldap-current/sbin:/opt/openldap-current/libexec:$PATH' >> /root/.bash_profile")
  raise 'LDAP DB Init failed' if ldap_host.transport.execute("cd /opt/openldap-current/etc/openldap && mkdir -p slapd.d && rm -rf slapd.d/* && slapadd -n 0 -F slapd.d -l slapd.ldif && chown -R ldap:ldap slapd.d && chmod -R o-rwx slapd.d && chown -R ldap:ldap /opt/openldap-current/var/openldap-data").exit_status > 0

  # Enable the service
  ldap_host.transport.execute("systemctl daemon-reload && systemctl start ldap && systemctl enable ldap")

  # Seed LDAP Data
  ldap_host.transport.putfile("/backup/ldap/ldap_seed_data.ldif", "/opt/openldap-current/etc/openldap/ldap_seed_data.ldif")
  raise 'Could not load seed data into LDAP' if ldap_host.transport.execute("ldapadd -D 'cn=ldapadm,dc=wpdev,dc=mintpress,dc=io' -w 'LinqvUt9hzR1mGkvBGYGvo' -a -f /opt/openldap-current/etc/openldap/ldap_seed_data.ldif").exit_status > 0
  
  # Seed the schema with SudoRole, note the user being used here is the admin of the schema
  raise 'Could not load seed sudorole into LDAP' if ldap_host.transport.execute("ldapadd -D 'cn=admin,cn=config' -w 'LinqvUt9hzR1mGkvBGYGvo' -a -f /opt/openldap-current/etc/openldap/schema/sudo.ldif").exit_status > 0
else
  Chef::Log.info 'LDAP Already exists. No Action'
end

# Find if PHPLDAPAdmin is installed
if !ldap_host.transport.File.exist?('/etc/phpldapadmin/config.php')
  Chef::Log.info 'PHPLDAPAdmin Does not exists. Downloading and installing..'
  ldap_host.transport.execute("yum install -y phpldapadmin mod_ssl")
  ldap_host.transport.putfile("/backup/ldap/ldap_php_config.php", "/etc/phpldapadmin/config.php")
  ldap_host.transport.putfile("/backup/ldap/ldap_http_ssl.conf", "/etc/httpd/conf.d/ssl.conf")
  ldap_host.transport.putfile("/backup/ldap/ldap_http_phpldapadmin.conf", "/etc/httpd/conf.d/phpldapadmin.conf")

  # Enable the service
  ldap_host.transport.execute("systemctl daemon-reload && systemctl start httpd && systemctl enable httpd")
else
  Chef::Log.info 'PHPLDAPAdmin Already exists. No Action'
end

ldap_host.remove_network_security_group_by_display_name(sec_group.display_name)
# update
ldap_host.update
sec_group.remove
