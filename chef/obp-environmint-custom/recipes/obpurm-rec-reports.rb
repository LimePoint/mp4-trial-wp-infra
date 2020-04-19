# Author: Harsha Gurram
# Recipe to configure Records Reports Festure

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']
asset_code = "obpurm"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"

admin_node = my_topology_vars["#{asset_code}"]['hostnameList'][0]
current_node = node.name.split('.')[0]

bash 'Copy required artefacts' do
	  code <<-EOH
	  	cp /oracle/stage/wcc/12.2.1.3/misc_files/xdo.runtime.ear /oracle/app/binaries/obpurm/fmw/wccontent/ucm/idc/components/ReportPublisher/lib/
	  	mv /oracle/app/binaries/obpurm/fmw/wccontent/ucm/idc/components/ServletPlugin/cs.ear /oracle/app/binaries/obpurm/fmw/wccontent/ucm/idc/components/ServletPlugin/cs.ear.orig 
	  	cp /oracle/stage/wcc/12.2.1.3/misc_files/cs.ear /oracle/app/binaries/obpurm/fmw/wccontent/ucm/idc/components/ServletPlugin/
	  	if [ $? -ne 0 ]; then 
	  		echo "Artefacts copy failed, Exiting"
	      	exit 1
	    else
	    	echo "Artefacts copied successfully"
	    fi
	    EOH
	end

if admin_node == current_node
	puts 'This is an Admin Node'	
	#Create wlst script to deploy xdo.runtime.ear Library
	template "Processing deployLibrary.py" do
		source "fmw/wlst/deployLibrary.py.erb"
		path "/tmp/deployLibrary.py"
		mode '0644'
		user 'oracle'
		group 'oinstall'
	end
	#Deploy Library
	bash 'Executing deployLibrary.py' do
	  code <<-EOH
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /tmp/deployLibrary.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} oracle.xdo.runtime /oracle/app/binaries/obpurm/fmw/wccontent/ucm/idc/components/ReportPublisher/lib urm_cluster stage
	  	if [ $? -ne 0 ]; then 
	  		echo "oracle.xdo.runtime Library Deployment Failed...Exiting"
	      	exit 1
	    else
	    	echo "oracle.xdo.runtime Library Deployment is successful"
	    fi
	    EOH
	end
else
	puts 'Not an Admin Node... Do Nothing'
end
