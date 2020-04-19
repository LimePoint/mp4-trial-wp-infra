# Author: Harsha Gurram
# Recipe to update perfdump parameter

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

base_dir = "/oracle/app/binaries/#{asset_code}/tmp"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"

template "Processing update_otd_perfdump.py" do
	source "fmw/wlst/update_otd_perfdump.py.erb"
	path "#{base_dir}/update_otd_perfdump.py"
	mode '0644'
	user 'oracle'
	group 'oinstall'
end
	
bash 'Executing update_otd_perfdump.py' do
  code <<-EOH
  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{base_dir}/update_otd_perfdump.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} all disable
  	if [ $? -ne 0 ]; then 
  		echo "OTD PerfDump update failed...Exiting"
      	exit 1
    else
    	echo "OTD PerfDump Update is successful"
    fi
    EOH
end
