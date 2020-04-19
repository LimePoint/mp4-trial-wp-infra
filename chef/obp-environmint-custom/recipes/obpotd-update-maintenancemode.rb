# Author: Harsha Gurram
# Recipe to Update Origin Server Pool Maintenance Mode.Requires input of asset_list and maintenance_mode.

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"
asset_list = node['build_vars']['asset_list']
m_mode = node['build_vars']['maintenance_mode']
puts "asset list is #{asset_list}"
puts "Maintenance Mode is to #{m_mode}"
base_dir = "/oracle/app/binaries/#{asset_code}/tmp"
username = "oracle"
groupname = "oinstall"
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
domain_home = "/oracle/app/runtime/obpotd/domains/obpotd_domain"

directory "#{domain_home}/maintenance_pages" do
  owner "oracle"
  group "oinstall"
  mode 0750
  recursive true
  action :create
  not_if { ::Dir.exists?("#{domain_home}/maintenance_pages") } 
end

cookbook_file "#{domain_home}/maintenance_pages/maintenance.html" do
  source 'otd_maintenance_pages/maintenance.html'
  owner "#{username}"
  group "#{groupname}"
  mode '0750'
  action :create
end

template "Processing update_otd_maintenance_mode.py" do
  source "fmw/wlst/update_otd_maintenance_mode.py.erb"
  path "#{base_dir}/update_otd_maintenance_mode.py"
  mode '0644'
  user 'oracle'
  group 'oinstall'
end

asset_csv = asset_list.join(",")
puts "Asset Array list is #{asset_csv}"
  
bash 'Executing update_otd_maintenance_mode.py' do
  code <<-EOH
    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{base_dir}/update_otd_maintenance_mode.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} #{asset_csv} #{m_mode}
    if [ $? -ne 0 ]; then 
      echo "OTD Maintenance Mode update failed...Exiting"
        exit 1
    else
      echo "OTD Maintenance Mode Update is successful"
    fi
    EOH
end