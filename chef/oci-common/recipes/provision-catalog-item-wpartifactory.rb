if node.run_state.key?('mintpress_action')
	mp_action = node.run_state['mintpress_action']
else
	mp_action = ''
end

host_opts = node.run_state['WPARTIFACTORY']['properties']['wpartifactory']
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

# Force the inputs for Artifactory coz we know better.
host_opts[:instance_type] = 'VM.Standard.E2.4'
host_opts[:operating_system] = 'Oracle Linux'
host_opts[:operating_system_version] = 7

# for artifactory we need more stroage 2TB
bds = [
 {name: 'var2', mount_point: '/var/opt', size_mb: 2097152} ]

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
    Chef::Log.info("No action specified. nothing to do!")
    return
end 

# This will kick in if provision
return unless mp_action == 'provision'

sec_group = MintPress::InfrastructureOci::OCINetworkSecurityGroup.new(
  display_name: "artifactory_god",
  vcn_id: oci_host.configs['oci_platform']['vcn_id'])

sec_list = MintPress::InfrastructureOci::OCISecurityGroupRule.new(
  network_security_group: sec_group,
  description: "rule to allow all external access to be used for installation. this rule is temporary and should not exist post install.",
  destination_type: "CIDR_BLOCK",
  destination: "0.0.0.0/0",
  direction: "EGRESS",
  protocol: 'all')

artifactory_host = oci_host.host_obj
delete_sec = false

# Install Artifactory if it not already is
if !artifactory_host.transport.File.exist?('/var/opt/jfrog/artifactory/tomcat/conf/server.xml')
  # Download and Install the binaries 
  Chef::Log.info 'Downloading Artifactory'
  sec_group.create
  sec_list.create

  artifactory_host.add_network_security_group_by_display_name(sec_group.display_name)
  artifactory_host.update

  delete_sec = true
 
  install_cmd = "yum install -y java && wget https://bintray.com/jfrog/artifactory-pro-rpms/rpm -O bintray-jfrog-artifactory-pro-rpms.repo && mv bintray-jfrog-artifactory-pro-rpms.repo /etc/yum.repos.d/ && yum install -y jfrog-artifactory-pro-6.13.1
" 
  raise 'Could not install and configure Artifactory' if artifactory_host.transport.execute(install_cmd).exit_status > 0 

  Chef::Log.info 'Artifactory Installed Successfully'
else
  Chef::Log.info 'Artifactory Already installed. Skipping'
end

# Transfer certs
Chef::Log.info 'Transferring Certs'
artifactory_host.transport.execute("mkdir -p /etc/caddy/ssl")
artifactory_host.transport.putfile("/backup/certs/server_cert.pem", "/etc/caddy/ssl/server_cert.pem")
artifactory_host.transport.putfile("/backup/certs/server_private_key.pem", "/etc/caddy/ssl/server_private_key.pem")
artifactory_host.transport.putfile("/backup/certs/certificate_chain.pem", "/etc/caddy/ssl/certificate_chain.pem")

# Check if Tomcat is configured for SSL
Chef::Log.info 'Checking if tomcat server.xml requires update'
conf_path = '/var/opt/jfrog/artifactory/tomcat/conf/server.xml'
Chef::Log.info "Reading server.xml from [#{conf_path}]"
serv_conf_content = artifactory_host.transport.content(conf_path) 
conf_params = {
  protocolHeader: "X-Forwarded-Proto",
  portHeader: "X-Forwarded-Port"
}
doc = Nokogiri::XML(serv_conf_content)
root = doc.root
con = doc.at_xpath("Server/Service/Engine/Host/Valve[@className='org.apache.catalina.valves.RemoteIpValve']")

if !con.nil? 
  Chef::Log.info "Conf file [#{conf_path}] already updated. Skipping..."
else
  # loop through the values and add them
  Chef::Log.info "Adding IPValve for Artifactory"
  Chef::Log.info 'Stopping Artifactory services'
  artifactory_host.transport.execute("systemctl stop artifactory")
  host_entry = doc.at_xpath("Server/Service/Engine/Host")
  host_entry.add_child('<Valve className="org.apache.catalina.valves.RemoteIpValve" protocolHeader="X-Forwarded-Proto" portHeader="X-Forwarded-Port" />')
  # write the file back
  Chef::Log.info "Updating conf file at [#{conf_path}]"
  artifactory_host.transport.File.write(conf_path, doc.to_xml)
  artifactory_host.transport.execute("systemctl start artifactory && systemctl enable artifactory")
end

# Downloading Caddy
if !artifactory_host.transport.File.exist?('/usr/local/bin/caddy')
  Chef::Log.info 'Downloading Caddy...'
  wget_cmd = "cd /tmp && wget https://github.com/caddyserver/caddy/releases/download/v1.0.3/caddy_v1.0.3_linux_amd64.tar.gz -O caddy.tar.gz && tar xzf caddy.tar.gz && mv caddy /usr/local/bin/caddy && rm -rf /tmp/caddy*"
  raise if artifactory_host.transport.execute(wget_cmd).exit_status > 0
  artifactory_host.transport.execute("chmod 755 /usr/local/bin/caddy && setcap 'cap_net_bind_service=+ep' /usr/local/bin/caddy && mkdir -p /etc/caddy")

  # Copy the service file
  Chef::Log.info 'Copying Caddy Conf files'
  artifactory_host.transport.erb_file('/backup/artifactory/caddy.service', '/etc/systemd/system/caddy.service', vars: {lb_install_user_name: 'artifactory', lb_install_group_name: 'artifactory'}) 
  artifactory_host.transport.erb_file('/backup/artifactory/Caddyfile', '/etc/caddy/Caddyfile')

  # Set the service/enable it and reload
  Chef::Log.info 'Enabling Caddy Service'
  artifactory_host.transport.execute('chmod 644 /etc/systemd/system/caddy.service && systemctl daemon-reload && systemctl enable caddy.service && systemctl start caddy.service')
else
  Chef::Log.info 'Caddy already installed, skipping.'
end

# Remove the group if was created
if delete_sec
  artifactory_host.remove_network_security_group_by_display_name(sec_group.display_name)
  artifactory_host.update
  sec_group.remove
end
