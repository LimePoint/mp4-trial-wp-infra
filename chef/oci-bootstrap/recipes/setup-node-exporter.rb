# This recipe has all configurations required for the LDAP server

group 'node_exporter' do
  system true
end

user 'node_exporter' do
  comment 'node exporter user'
  gid 'node_exporter'
  system true
  shell '/sbin/nologin'
end

cookbook_file "/etc/init.d/node_exporter" do
  source "node_exporter.initd"
  mode '0755'

  notifies :run, 'execute[create_directory]', :immediate
  only_if { node['platform_version'].to_i < 7 }
end

cookbook_file "/etc/sysconfig/node_exporter" do
  source "sysconfig.node_exporter"
  mode '0744'

  notifies :run, 'execute[create_directory]', :immediate
  only_if { node['platform_version'].to_i >= 7 }
end

cookbook_file "/etc/systemd/system/node_exporter.service" do
  source "node_exporter.service"
  mode '0744'

  notifies :run, 'execute[reload_systemd]', :immediate
  notifies :run, 'execute[copy_binary]', :immediate
  only_if { node['platform_version'].to_i >= 7 }
end

execute "create_directory" do
  command "mkdir -p /opt/node_exporter /var/lib/node_exporter/textfile_collector && chown -R node_exporter:node_exporter /opt/node_exporter /var/lib/node_exporter"

  action :nothing
end

execute "copy_binary" do
  command "cp -u /oracle/stage/node_exporter/node_exporter /opt/node_exporter/node_exporter"
  user 'node_exporter'

  action :nothing
end

execute "reload_systemd" do
  command "systemctl daemon-reload"

  action :nothing
  only_if { node['platform_version'].to_i >= 7 }
end

service 'node_exporter' do
  action :enable
end 

service 'node_exporter' do
  action :start
end 
