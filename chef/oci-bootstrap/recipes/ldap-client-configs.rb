# Call the ldap recipe from the ldap cookbook
# The credentials used are in the default attributes

hostlist=[]
search(:node, "chef_environment:#{node.chef_environment}").each do |r|
	begin
		hostlist << r['hostname'].split('.')[0]
	rescue
		# do nothing
	end
end

# [RB] - It seems that the search query above does not work if FQDN is not set for the node. 
# The FQDN should be set during the bootstrap (see bug MINTPRESS-2166) but alternatively chef autosets it once a chef-client has run successfully
if hostlist.empty?
  Chef::Log.info("HostList is empty, skipping adding ldap entries. This will auto fix in next run")
  return
end
  
#ldap_entry "cn=host_#{node.name.split('.')[0]},ou=host,ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
#	attributes ({objectClass: ['top', 'nisNetgroup']})
#	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
#	host node['ldap']['ldap_host']
#	port node['ldap']['ldap_port']
#	use_tls true
#end

# Create the super admin team, members of this group will have root acesss to every node
# It does not looks like it is used anywhere though
ldap_entry "cn=team_obp_all_root,ou=team,ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'nisNetgroup']})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

# Create the environment specific root team, this will allow members to access hosts in this environment as root
ldap_entry "cn=team_obp_#{node.chef_environment}_root,ou=team,ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'nisNetgroup']})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

# Oracle team, allows members to access as oracle user
ldap_entry "cn=team_obp_#{node.chef_environment}_oracle,ou=team,ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'nisNetgroup']})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

# Team for read only
ldap_entry "cn=team_obp_#{node.chef_environment}_readonly,ou=team,ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'nisNetgroup']})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

# put teams in host netgroup
ldap_entry "cn=host_#{node.name.split('.')[0]},ou=host,ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'nisNetgroup'], memberNisNetgroup: ["team_obp_#{node.chef_environment}_root", "team_obp_#{node.chef_environment}_oracle", "team_obp_#{node.chef_environment}_readonly"]})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

# Create sudo for team, oracle
ldap_entry "cn=obp_sudo_#{node.chef_environment}_root,ou=sudo,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'sudoRole'], sudoRunAsUser: 'root', sudoUser: ["+team_obp_#{node.chef_environment}_root", "+team_obp_all_root"], sudoCommand: 'ALL', sudoHost: hostlist})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

ldap_entry "cn=obp_sudo_#{node.chef_environment}_oracle,ou=sudo,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'sudoRole'], sudoRunAsUser: 'oracle', sudoUser: ["+team_obp_#{node.chef_environment}_oracle"], sudoCommand: 'ALL', sudoHost: hostlist})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

ldap_entry "cn=obp_sudo_#{node.chef_environment}_su_oracle,ou=sudo,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io" do
	attributes ({objectClass: ['top', 'sudoRole'], sudoRunAsUser: 'root', sudoUser: ["+team_obp_#{node.chef_environment}_oracle"], sudoCommand: '/bin/su - oracle', sudoHost: hostlist})
	credentials ({'bind_dn' => node['sssd_ldap']['sssd_conf']['ldap_default_bind_dn'], 'password' => node['sssd_ldap']['sssd_conf']['ldap_default_authtok']})
	host node['ldap']['ldap_host']
	port node['ldap']['ldap_port']
	use_tls true
end

file "/etc/security/access.conf" do
	content <<-EOH
+:root:ALL
+:opc:ALL
+:oracle:ALL
+:mintpress:ALL
+:@host_#{node.name.split('.')[0]}:ALL
-:ALL:ALL
	EOH
end

file "/etc/pam.d/sshd" do
	content <<-EOH
#%PAM-1.0
auth       required     pam_sepermit.so
auth       include      password-auth
account    required     pam_nologin.so
account required pam_access.so #insert this module
account    include      password-auth
password   include      password-auth
# pam_selinux.so close should be the first session rule
session    required     pam_selinux.so close
session    required     pam_loginuid.so
# pam_selinux.so open should only be followed by sessions to be executed in the user context
session    required     pam_selinux.so open env_params
session    required     pam_namespace.so
session    optional     pam_keyinit.so force revoke
session    include      password-auth
	EOH
end

