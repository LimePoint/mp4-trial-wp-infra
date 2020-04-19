# Author: Harsha Gurram
# Recipe to restart SSL channels to pick up new certificates of WLS domain. 


environment_name = node.chef_environment.downcase
#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
local_asset = "obp#{item_code}"

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Create wlst script to restart WLS SSL Channels
template "Processing restart_wls_ssl.py" do
  source "fmw/wlst/restart_wls_ssl.py.erb"
  path "/tmp/restart_wls_ssl.py"
  mode '0644'
end

asset_list = ['obpbip','obpsoa','obpobh','obpobu','obpdoc','obpipm','obpurm','obpoim','obpcim','obpodi','obpoid','obpcid','obposb','obpoam']

asset_list.each do |asset_code|
  domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
  weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
  weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"
  #Restart WLS SSL Channels 
  bash 'Executing restart_wls_ssl.py' do
    code <<-EOH
      /oracle/app/binaries/#{local_asset}/fmw/oracle_common/common/bin/wlst.sh /tmp/restart_wls_ssl.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
      if [ $? -ne 0 ]; then 
        echo "WLS SSL channel restart failed...Exiting"
          exit 1
      else
        echo "WLS SSL channel restart is successful"
      fi
    EOH
  end
end
