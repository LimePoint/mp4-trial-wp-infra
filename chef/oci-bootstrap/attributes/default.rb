# LDAP Entries
node.override['sssd_ldap']['sssd_conf']['ldap_uri']='ldaps://ldap-alpha.wpdev.mintpress.io:636'
node.override['sssd_ldap']['sssd_conf']['ldap_search_base']='dc=wpdev,dc=mintpress,dc=io'
node.override['sssd_ldap']['sssd_conf']['ldap_user_search_base']='ou=account,dc=wpdev,dc=mintpress,dc=io'
node.override['sssd_ldap']['sssd_conf']['ldap_group_search_base']='ou=group,dc=wpdev,dc=mintpress,dc=io'
node.override['sssd_ldap']['sssd_conf']['ldap_netgroup_search_base']='ou=netgroup,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io'
node.override['sssd_ldap']['sssd_conf']['ldap_sudo_search_base']='ou=sudo,ou=obp,ou=app,dc=wpdev,dc=mintpress,dc=io'
node.override['sssd_ldap']['sssd_conf']['ldap_default_bind_dn']='cn=ldap_readonly,dc=wpdev,dc=mintpress,dc=io'
node.override['sssd_ldap']['sssd_conf']['ldap_default_authtok']='twub!LEF8jeff1werm'
node.override['sssd_ldap']['sssd_conf']['entry_cache_timeout']='300'
node.override['sssd_ldap']['ldap_ssh']=true
node.override['sssd_ldap']['ldap_sudo']=true
node.override['openssh']['server']['authorized_keys_command']='/usr/bin/sss_ssh_authorizedkeys'
node.override['openssh']['server']['authorized_keys_command_user'] = 'root' if node['platform_version'].to_f >= 7.0
node.override['openssh']['server']['password_authentication']='yes'
node.override['authconfig']['mkhomedir'] = true
node.override['authconfig']['sssd']['enable'] = true

# How to reach LDAP
default['ldap']['ldap_host']='ldap-alpha.wpdev.mintpress.io'
default['ldap']['ldap_port']=636

# which stage to mount
default['stage']['host']='stage.alpha.wpdev.mintpress.io'
