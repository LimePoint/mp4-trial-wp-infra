# Set the TZ to AU
timezone 'Australia/Sydney'

# Disable the Firewalld Service
service 'firewalld' do
  action :stop
end

service 'firewalld' do
  action :disable
end

# Create the MintPress Group
group 'mintpress' do
  comment 'Group for MintPress User'
  gid 1011
end

# Create the MintPress user
user 'mintpress' do
  comment 'User for MintPress'
  uid 601
  gid 'mintpress'
  home '/home/mintpress'
  shell '/bin/bash'
  manage_home true
end

# Create the .ssh directory
directory '/home/mintpress/.ssh' do
  owner 'mintpress'
  group 'mintpress'
  mode '0700'
end

# Create the Oracle Group
group 'oinstall' do
  comment 'Group for Oracle User'
  gid 5001
end

# Create the Oracle user
user 'oracle' do
  comment 'User for Oracle'
  uid 5001
  gid 'oinstall'
  home '/home/oracle'
  shell '/bin/bash'
  manage_home true
end

# Create additional groups if this is a DB node
if node.name.split(".")[0][-2..-1] == 'db'
  db_groups = ['backupdba','dgdba','kmdba','dba','oper','backupdba','racdba'] 
  db_groups.each do | gp | 
    group gp  do
      comment "Group for #{gp}" 
      members 'oracle'
    end
  end
end

# Create the .ssh directory
directory '/home/oracle/.ssh' do
  owner 'oracle'
  group 'oinstall'
  mode '0700'
end

# Install Standard Packages, this must be before updating the resolv.conf. 
# This order helps reduce the time it takes to install the packages
include_recipe '::oracle-packages'

# Set the resolv.conf to the internal DNS servers
template '/etc/resolv.conf' do
  source 'resolv.conf'
  owner 'root'
  group 'root'
end

# Make the resolv.conf file immutable coz VM reboot will override this file and then nothing will work
execute 'chattr +i /etc/resolv.conf' 

# Create the directory for stage mount, we have to use execute coz directory resource fails on subsequent runs
# It tries to create the directory which by that point has become a mount, and throws Read-only file system @ apply2files - /oracle/stage
execute 'mkdir -p /oracle/stage'

### --- Set up SSSD For LDAP Authentication --- ###
# Setup the SSSD Subsystem. This is from the sssd_ldap cookbook
include_recipe 'sssd_ldap'

# We then clear up the cache
execute '/usr/sbin/sss_cache -E' do
  ignore_failure true
end

# Set the sshd_config
template '/etc/ssh/sshd_config' do
  source 'sshd_config'
  owner 'root'
  group 'root'
  mode '0600'

  notifies :restart, 'service[sshd]', :immediately
end

# This is required to create home directories for the LDAP users
execute "authconfig --enablemkhomedir --update"

# Ensure /oracle is owned by Oracle
directory '/oracle' do
  owner 'oracle'
  group 'oinstall'
end


# Add the Authorized keys for mintpress user
# This allows MintPress application to logon to all users
template '/home/mintpress/.ssh/authorized_keys' do
  source 'mintpress-authz'
  owner 'mintpress'
  group 'mintpress'
  mode '0600'
end

# Ensure oracle user can run chef-client
directory '/home/oracle/chef' do
  owner 'oracle'
  group 'oinstall'
end

# Add the client.rb to /home/oracle/chef for middleware to use
remote_file '/home/oracle/chef/client.rb' do
  source 'file:///etc/chef/client.rb'
  owner 'oracle'
  group 'oinstall'
  mode '0600'
end

# Add oracle limits
template "/etc/security/limits.d/oracle.conf" do
  source "limits/oracle.conf"
  owner 'root'
  group 'root'
end

# Cleanup the Auditor logs
# cleanup _all_ defaultauditrecorder files
# TODO: Harsha to fix this as this might be deleting files that are being used
execute 'rm -f /oracle/app/runtime/*/domains/*/servers/*/logs/DefaultAuditRecorder.* /oracle/app/logs/*/*/*/DefaultAuditRecorder.*' do
  ignore_failure true
end

# Required for LDAP
gem_package "net-ldap"

gem_package "cicphash" 

# Include recipe for adding VM into the LDAP
include_recipe '::ldap-client-configs'

# RB: Do this to for a workaround on sudoers not working;
# RB: there is no guarantee that this fixes it but this has worked all the time
service 'sssd' do
  action :restart
end

# Make the chef-client a system service unless you are running oel6 (for och)
if node['platform_version'].to_i < 7
  service 'iptables' do
    action :stop
  end

  service 'iptables' do
    action :disable
  end

  service 'ip6tables' do
    action :stop 
  end

  service 'ip6tables' do
    action :disable
  end

  include_recipe 'chef-client::init_service'
else
  include_recipe 'chef-client::systemd_service'
end 

# Asset specific recipes
if node.name.include?('doc')
	include_recipe "::batch-folders"
end

# Make mint not complain about the host keys
# This is required since we regularly re-build VMs
if ['mintpress-deployments.wpdev.mintpress.io', 'mintpress-alpha.wpdev.mintpress.io','mintpress-omega.wpdev.mintpress.io', 'mintpress-beta.wpdev.mintpress.io'].include?(node.name)
	file "/home/mintpress/.ssh/config" do
		content <<-EOH
Host obpc*
Stricthostkeychecking no
Userknownhostsfile /dev/null
		EOH

	owner 'mintpress'
	group 'mintpress'
	mode '0600'
	end
    
    # Add the sudoers for MintPress product to interact with chef
    template '/etc/sudoers.d/mintpress' do
      source 'sudoers-mintpress-chef'
      owner 'root'
      group 'root'
    end

    # Add the mounts in rw mode
    mount '/oracle/stage' do
      device 'stage.wpdev.mintpress.io:/stage'
      fstype 'nfs'
      options 'rw'
    end
else
    # Add the sudoers for MintPress user
    template '/etc/sudoers.d/mintpress' do
      source 'sudoers-mintpress'
      owner 'root'
      group 'root'
    end
    
    # Add the mounts in ro mode 
    mount '/oracle/stage' do
      device 'stage.wpdev.mintpress.io:/stage'
      fstype 'nfs'
      options 'ro'
  end
end

# Restart SSHD only if required
service 'sshd' do
  action :nothing
end

# This will setup Prometheus Node Exporter on the targets
include_recipe '::setup-node-exporter'
