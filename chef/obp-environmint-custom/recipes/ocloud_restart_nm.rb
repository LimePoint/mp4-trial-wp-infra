# Author: Harsha Gurram
# Recipe to restart SSL channels to pick up new certificates of WLS domain. 


environment_name = node.chef_environment.downcase

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

#Create script to restart NodeManager
template "Processing restart_nm.sh" do
  source "fmw/restart_nm.sh.erb"
  path "/tmp/restart_nm.sh"
  mode '0644'
  user 'oracle'
  group 'oinstall'
end

#Restart NodeManager
bash 'Executing restart_nm.sh' do
  code <<-EOH
    sh /tmp/restart_nm.sh #{asset_code}
    if [ $? -ne 0 ]; then 
      echo "NM restart failed... Exiting"
        exit 1
    else
      echo "NM Update Job successful"
    fi
    EOH
end