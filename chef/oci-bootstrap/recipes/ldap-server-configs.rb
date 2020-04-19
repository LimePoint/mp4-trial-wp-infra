# This recipe has all configurations required for the LDAP server

template "/etc/security/limits.d/ldap.conf" do
  source "limits/ldap.conf"
  owner 'root'
  group 'root'
end

group 'ldap' do
  system true
end

user 'ldap' do
  comment 'ldap user'
  uid 603
  gid 'ldap'
  system true
  shell '/bin/false'
end

