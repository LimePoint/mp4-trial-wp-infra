# Author: Harsha Gurram
# Recipe to update certificate of WLS domain and restart SSL channels and NodeManager

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
asset_hostname = node['renew_asset']
item_code = asset_hostname.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"
keystore_name = my_topology_vars["#{asset_code}"]['hostnameList'][0][0...-2]
certs_source_path = "/oracle/stage/certs/csh/#{environment_name}/#{keystore_name}.jks"
certs_dest_path = "/oracle/app/runtime/#{environment_name}/certs/#{keystore_name}.jks"
puts certs_dest_path
puts certs_source_path

admin_node = my_topology_vars["#{asset_code}"]['hostnameList'][0]
current_node = asset_hostname.split('.')[0]

if admin_node == current_node
	puts 'This is an Admin Node'
	#Copy keystore to domain cert location
	bash 'Copy Keystore' do
	  code <<-EOH
	  	rsync --checksum #{certs_source_path} #{certs_dest_path}
	  	if [ $? -ne 0 ]; then 
	  		echo "KeyStore copy failed, Exiting"
	      	exit 1
	    else
	    	echo "Keystore copied successfully"
	    fi
	    EOH
	end
	#Create wlst script to restart WLS SSL Channels
	template "Processing restart_wls_ssl.py" do
		source "fmw/wlst/restart_wls_ssl.py.erb"
		path "/tmp/restart_wls_ssl.py"
		mode '0644'
		user 'oracle'
		group 'oinstall'
	end
	#Restart WLS SSL Channels	
	bash 'Executing restart_wls_ssl.py' do
	  code <<-EOH
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /tmp/restart_wls_ssl.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
	  	if [ $? -ne 0 ]; then 
	  		echo "WLS SSL channel restart failed...Exiting"
	      	exit 1
	    else
	    	echo "WLS SSL channel restart is successful"
	    fi
	    EOH
	end
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
	    echo|openssl s_client -connect #{admin_node}:18001 2> /dev/null | openssl x509 -noout -dates
	    EOH
	end
else
	puts 'Not an Admin Node'

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
end
