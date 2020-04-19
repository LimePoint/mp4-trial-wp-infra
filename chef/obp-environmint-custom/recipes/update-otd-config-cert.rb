# Author: Harsha Gurram
# Recipe to update OTD config Keystores

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
otd_config_list = ""
otd_ks_pw = ""
otd_configs = my_topology_vars["#{asset_code}"]['otd_config']

#Make list of keystore passwords
otd_configs.each do |otd_config, value| 
	unless otd_config == 'base_routerId'
	pwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{otd_config}/keystorepass").value)
	otd_config_list << otd_config + ","
	otd_ks_pw << pwd + ","
	end
end

template "Processing update_otd_cert.py" do
	source "fmw/wlst/update_otd_cert.py.erb"
	path "#{base_dir}/update_otd_cert.py"
	mode '0644'
	user 'oracle'
	group 'oinstall'
end
	
bash 'Executing update_otd_cert.py' do
  code <<-EOH
  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{base_dir}/update_otd_cert.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} #{otd_config_list} #{otd_ks_pw} #{environment_name}
  	if [ $? -ne 0 ]; then 
  		echo "OTD Cert update failed...Exiting"
      	exit 1
    else
    	echo "OTD Cert Update is successful"
    fi
    EOH
end
