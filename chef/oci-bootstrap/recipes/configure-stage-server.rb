# This recipe ensures that the NFS server is configured on stage.wpdev.mintpress.io

yum_package 'nfs-utils' 
yum_package 'rpcbind' 

# Enable all services
nfs_services = ['nfs-server', 'rpcbind', 'nfs-lock', 'nfs-idmap']
nfs_services.each do | svc |
  service svc do
    action :enable
  end

  service svc do
    action :start
  end
end

template "/etc/exports" do
  source "stage-exports"
  owner 'root'
  group 'root'

  notifies :run, 'execute[reload_exports]', :immediately
end

execute 'reload_exports' do
  command 'exportfs -r'
end
