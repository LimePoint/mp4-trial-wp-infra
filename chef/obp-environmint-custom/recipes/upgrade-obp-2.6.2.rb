# Author: Harsha Gurram
require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)
# Recipe to ugrade OBP from 2.6.1 to 2.6.2

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
obpsoa_adminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpsoa_admin").value)
release_version = my_topology_vars["#{asset_code}"]['release_version']

if release_version != '2.6.2'
	Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
	return
end

if ['obpobh','obpobu'].include?(asset_code)
	bash 'Backup setDomainEnv.sh' do
	  code <<-EOH
	    cp -p /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setDomainEnv.sh /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setDomainEnv.sh.2.6.1.bkp
	    touch /oracle/app/binaries/#{asset_code}/fmw/obpinstall/.mint_obp_lzn
	    EOH
	  not_if { ::File.exist?("/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setDomainEnv.sh.2.6.1.bkp") }
	  Chef::Log.info('setDomainEnv.sh backed up.')
	end
else
	Chef::Log.info('Doesnt apply to this domain')
end

if ['obpobu'].include?(asset_code)
	config_file  = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setDomainEnv.sh"
	ruby_block "Modify setDomainEnv.sh file #{config_file}" do
		  block do

		    file = Chef::Util::FileEdit.new(config_file)
		    
		    file.search_file_replace_line(/obp.thirdparty.domain/, "PRE_CLASSPATH=\"\$\{OBP_ORACLE_HOME\}/config:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-annotations-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-core-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-databind-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-module-jaxb-annotations-2.9.5.jar:\$\{WL_HOME\}/modules/databinding.override.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/json-20180130.jar:\$\{PRE_CLASSPATH\}\"")
		    file.search_file_delete(/-Dobp.http.staleCheckEnabled=true -Dobp.http.idleTimeoutPollInterval=10000 -Dobp.http.maxRetryCount=3 -Dobp.http.socketBufferSize=8192 -Dobp.http.maxConnectionsPerHost=150 -Dobp.http.connectionTimeout=600000 -Dobp.http.expireAndRetry=false/)
		    file.search_file_delete(/-Dobp.http.idleTimeoutPollInterval=10000 -Dobp.http.maxRetryCount=3 -Dobp.http.socketBufferSize=8192 -Dobp.http.maxConnectionsPerHost=150 -Dobp.http.connectionTimeout=600000 -Dobp.http.expireAndRetry=false/)
		    file.write_file
		  end
	end
end

if ['obpobh'].include?(asset_code)
	config_file  = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setDomainEnv.sh"
	ruby_block "Modify setDomainEnv.sh file #{config_file}" do
		  block do

		    file = Chef::Util::FileEdit.new(config_file)
		    
		    file.search_file_replace_line(/obp.thirdparty.domain/, "PRE_CLASSPATH=\"\$\{OBP_ORACLE_HOME\}/config:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/jackson-annotations-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/jackson-core-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/jackson-databind-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/jackson-module-jaxb-annotations-2.9.5.jar:\$\{WL_HOME\}/modules/databinding.override.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/groovy-all-2.4.13.jar:/oracle/app/binaries/obpobh/fmw/oracle_common/modules/javax.jms.javax.jms-api.jar:/oracle/app/binaries/obpobh/fmw/wlserver/server/lib/weblogic.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/xmlparserv2-12.1.0.2.0.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/slf4j-api-1.7.25.jar:\$\{OBP_ORACLE_HOME\}/ob.host.app/ob.app.host.tp/APP-INF/lib/json-20180130.jar:\$\{PRE_CLASSPATH\}\"")
		    file.search_file_delete(/-Dobp.http.staleCheckEnabled=true -Dobp.http.idleTimeoutPollInterval=10000 -Dobp.http.maxRetryCount=3 -Dobp.http.socketBufferSize=8192 -Dobp.http.maxConnectionsPerHost=150 -Dobp.http.connectionTimeout=600000 -Dobp.http.expireAndRetry=false/)
		    file.search_file_delete(/-Dobp.http.idleTimeoutPollInterval=10000 -Dobp.http.maxRetryCount=3 -Dobp.http.socketBufferSize=8192 -Dobp.http.maxConnectionsPerHost=150 -Dobp.http.connectionTimeout=600000 -Dobp.http.expireAndRetry=false/)
		    file.write_file
		  end
	end
end

if ['obpsoa'].include?(asset_code)
	bash 'Backup setStartupEnvSOA.sh and setStartupEnv.sh' do

	  code <<-EOH
	    cp -p /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnvSOA.sh /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnvSOA.sh.2.6.1.bkp
	    cp -p /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnv.sh /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnv.sh.2.6.1.bkp
	    touch /oracle/app/binaries/#{asset_code}/fmw/obpinstall/.mint_obp_lzn
	    EOH
	  not_if { ::File.exist?("/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnvSOA.sh.2.6.1.bkp") }
	  Chef::Log.info('setStartupEnvSOA.sh and setStartupEnv.sh backed up.')
	end
else
	Chef::Log.info('Doesnt apply to this domain')
end

if ['obpsoa'].include?(asset_code)
	config_file  = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnvSOA.sh"
	ruby_block "Modify setStartupEnvSOA.sh file #{config_file}" do
		  block do

		    file = Chef::Util::FileEdit.new(config_file)
		    
		    file.search_file_replace_line(/obp.thirdparty.domain/, "PRE_CLASSPATH=\"\$\{OBP_ORACLE_HOME\}/config:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-annotations-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-core-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-databind-2.9.5.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/jackson-module-jaxb-annotations-2.9.5.jar:\$\{WL_HOME\}/modules/databinding.override.jar:\$\{OBP_ORACLE_HOME\}/ob.ui.web/ob.ui.tp/WEB-INF/lib/json-20180130.jar:\$\{PRE_CLASSPATH\}\"")
		    file.search_file_replace_line(/-Djbo.ampool.doampooling=false/, "SERVER_MEM_ARGS_64HotSpot=\"-Xms1024m -Xmx2048m -XX:PermSize=512m -XX:MaxPermSize=1024m\"")
		    file.search_file_replace(/-Xms8192m -Xmx18432m/, "-Xms11g -Xmx11g")
		    file.search_file_replace(/soa_server1"/, "soa_server\"*")
		    file.write_file
		  end
	end
	config_file2  = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/bin/setStartupEnv.sh"
	ruby_block "Modify setStartupEnv.sh file #{config_file2}" do
		  block do

		    file = Chef::Util::FileEdit.new(config_file2)
		    
		    file.search_file_replace(/soa_server1"/, "soa_server\"*")
		    file.search_file_replace(/bam_server1"/, "bam_server\"*")
		    file.write_file
		  end
	end
	bash 'Copy artefacts from MP' do

	  code <<-EOH
	    cp -vf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/ob.ht.workflow/ob.ht.workflow.fw/approvalgroup/com.ofss.fc.workflow.dynamic.approvalgroup.jar /oracle/app/binaries/obpsoa/fmw/soa/soa/modules/oracle.soa.ext_11.1.1/;
	    cp -vf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/ob.ht.workflow/ob.ht.workflow.fw/framework/faultManagement/com.ofss.fc.workflow.fault.management.jar /oracle/app/binaries/obpsoa/fmw/soa/soa/modules/oracle.soa.ext_11.1.1/;
	    cp -vf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/ob.ht.workflow/ob.ht.workflow.fw/approvalgroup/oracle.soa.ext.jar /oracle/app/binaries/obpsoa/fmw/soa/soa/modules/oracle.soa.ext_11.1.1/;
	    cp -rvf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/BPELRecoveryConfig /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/BPELRecoveryConfig;
	    cd /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/BPELRecoveryConfig;
	    unzip -u BPELRecoveryConfig.zip;
	    cp -rvf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/soaTaskflowGrants /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/soaTaskflowGrants;
	    cp -rvf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/soaGrantAndPolicySet /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/soaGrantAndPolicySet;
	    cp -rvf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/worklist /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist;
	    cp -vf /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/binaries/obpinstall/obp/ob.ui.client/ob.app.client.fw/WEB-INF/lib/com.ofss.fc.object.cache.jar /oracle/app/runtime/obpsoa/domains/obpsoa_domain/lib/;
	    touch /oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2.upgrade_skip
	    EOH
	  not_if { ::File.exist?("/oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2.upgrade_skip") }
	  Chef::Log.info('SOA 2.6.2 artifacts copied')
	end

end


if ['obpobh','obpobu'].include?(asset_code)
	Chef::Log.info('Connecting to domain -')
	Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
	Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

	Chef::Log.info("Creating WLST ")

	template 'upgrade-#{asset_code}-2.6.2.py' do
	  source "fmw/2.6.2/upgrade-#{asset_code}-2.6.2.py.erb"
	  path "/oracle/app/binaries/tmp/upgrade-#{asset_code}-2.6.2.py"
	  mode '0700'
	end

	bash 'Upgrading Domain to 2.6.2' do
	  code <<-EOH
	    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/upgrade-#{asset_code}-2.6.2.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
	    EOH
	end
end

if ['obpsoa'].include?(asset_code)
	Chef::Log.info('Connecting to domain -')
	Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
	Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

	Chef::Log.info("Creating WLST ")

	template 'upgrade-#{asset_code}-2.6.2.py' do
	  source "fmw/2.6.2/upgrade-#{asset_code}-2.6.2.py.erb"
	  path "/oracle/app/binaries/tmp/upgrade-#{asset_code}-2.6.2.py"
	  mode '0700'
	end

	template 'obpsoa-2.6.2-upgrade-fix.sql' do
	  source "sql/obpsoa-2.6.2-upgrade-fix.sql.erb"
	  path "/oracle/app/binaries/tmp/obpsoa-2.6.2-upgrade-fix.sql"
	  mode '0700'
	end

	bash 'Upgrading Domain to 2.6.2' do
	  code <<-EOH
	    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/upgrade-#{asset_code}-2.6.2.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} upgradeApps
	    EOH
	end
	Chef::Log.info('Recreate default SOA partition')
	bash 'Drop And Recreate SOA Partition Domain to 2.6.2' do
	  code <<-EOH
	    /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/upgrade-#{asset_code}-2.6.2.py weblogic #{weblogicAdminPassword} t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17002 recreateSOAPartition
	    touch /oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2.upgrade_droppartition;
	    EOH
	  not_if { ::File.exist?("/oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2.upgrade_droppartition") }  
	end

	Chef::Log.info('Executing SOA flexfields attr DB Fix ')
	oracle_sql "/oracle/app/binaries/tmp/obpsoa-2.6.2-upgrade-fix.sql" do
	oracle_home '/oracle/stage/oracle_client/12.1.0/client_1'
	db_service_name my_topology_vars['obpsoa']['database']['service_name']
	db_host my_topology_vars['obpsoa']['database']['scan_address']
	db_port my_topology_vars['obpsoa']['database']['listen_port'].to_i
	db_username "OBPSOA_SOAINFRA"
	db_password Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpsoa/OBPSOA").value)
	as_sysdba false
	sql_file "/oracle/app/binaries/tmp/obpsoa-2.6.2-upgrade-fix.sql"
	action :run
	user 'oracle'
	group 'oinstall'
	not_if { ::File.exist?("/oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2_obpsoa_db_fix.skip") } 
	end

	bash 'Check to skip soa db fix' do
	  code <<-EOH
	    touch /oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2_obpsoa_db_fix.skip;
	    EOH
	  not_if { ::File.exist?("/oracle/app/binaries/obpsoa/fmw/obpinstall/.2.6.2_obpsoa_db_fix.skip") } 
	end

	Chef::Log.info('Executing BPELRecoveryConfig...')

	bash 'Execute BPELRecoveryConfig' do
	  code <<-EOH
	  	export JAVA_HOME=/oracle/app/binaries/#{asset_code}/java
		export PATH=$JAVA_HOME/bin:$PATH;
		cd /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/BPELRecoveryConfig;
		java -cp BPELRecoveryConfig.jar:/oracle/app/binaries/#{asset_code}/fmw/wlserver/server/lib/weblogic.jar com.ofss.fc.utils.install.jmx.UpdateBPELRecoveryConfig #{my_topology_vars["#{asset_code}"]['admin']['listen_address']} 17002 weblogic #{weblogicAdminPassword}
	    EOH
	end

	Chef::Log.info('Running Task Flow Grants ')

	bash 'Execute Task Flow Grants' do
	  code <<-EOH
	  	cd /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/soaTaskflowGrants;
	  	echo 'Calling soaTaskflowGrants1.py...';
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh soaTaskflowGrants1.py weblogic #{weblogicAdminPassword} #{my_topology_vars["#{asset_code}"]['admin']['listen_address']} 17001
	  	echo 'Calling soaTaskflowGrants2.py...';
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh soaTaskflowGrants2.py weblogic #{weblogicAdminPassword} #{my_topology_vars["#{asset_code}"]['admin']['listen_address']} 17001
	  	echo 'Calling soaTaskflowGrants3.py...';
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh soaTaskflowGrants3.py weblogic #{weblogicAdminPassword} #{my_topology_vars["#{asset_code}"]['admin']['listen_address']} 17001
	  	echo 'Calling soaTaskflowGrants4.py...';
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh soaTaskflowGrants4.py weblogic #{weblogicAdminPassword} #{my_topology_vars["#{asset_code}"]['admin']['listen_address']} 17001
	    EOH
	end

	Chef::Log.info('Running soaGrantAndPolicySet ')

	bash 'Execute soaGrantAndPolicySet' do
	  code <<-EOH
	  	cd /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/soaGrantAndPolicySet;
	  	echo 'Calling soaGrantAndPolicySet.py...';
	  	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh soaGrantAndPolicySet.py obpsoa_domain /oracle/app/runtime/obpsoa/domains weblogic #{weblogicAdminPassword} #{my_topology_vars["#{asset_code}"]['admin']['listen_address']} 17001
	    EOH
	end

	Chef::Log.info('Running migrateWorklist-flexfields-import.sh ')

	bash 'Execute migrateWorklist-flexfields-import.sh' do
	  code <<-EOH
	  	cd /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist;
	  	sed -i 's/user = weblogic/user = obpsoa_admin/g' migration-flexfields-import.properties;
	  	export MW_HOME=/oracle/app/binaries/obpsoa/fmw;
		. /oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/commEnv.sh;
		ant -f /oracle/app/binaries/obpsoa/fmw/soa/bin/ant-t2p-worklist.xml -Dbea.home=/oracle/app/binaries/obpsoa/fmw -Dsoa.home=/oracle/app/binaries/obpsoa/fmw/soa -Dmigration.properties.file=/oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist/migration-flexfields-import.properties -Dsoa.hostname=#{my_topology_vars["#{asset_code}"]['admin']['listen_address']} -Dsoa.rmi.port=17002 -Dsoa.admin.user=obpsoa_admin -Dsoa.admin.password=#{obpsoa_adminPassword} -Drealm=jazn.com -Dmigration.file=/oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist/export_all_flexfields.xml -Dmap.file=/oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist/export_all_flexfields_mapper.xml
	    EOH
	end

	Chef::Log.info('Running migrateWorklist-views-import.sh ')

	bash 'Execute migrateWorklist-views-import.sh' do
	  code <<-EOH
	  	cd /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist;
	  	sed -i 's/user = weblogic/user = obpsoa_admin/g' migration-views-import.properties;	  	
	  	export MW_HOME=/oracle/app/binaries/obpsoa/fmw;
		. /oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/commEnv.sh;
		ant -f /oracle/app/binaries/obpsoa/fmw/soa/bin/ant-t2p-worklist.xml -Dbea.home=/oracle/app/binaries/obpsoa/fmw -Dsoa.home=/oracle/app/binaries/obpsoa/fmw/soa -Dmigration.properties.file=/oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist/migration-views-import.properties -Dsoa.hostname=#{my_topology_vars["#{asset_code}"]['admin']['listen_address']} -Dsoa.rmi.port=17002 -Dsoa.admin.user=obpsoa_admin -Dsoa.admin.password=#{obpsoa_adminPassword} -Drealm=jazn.com -Dmigration.file=/oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist/export_all_views.xml -Dmap.file=/oracle/app/binaries/obpsoa/fmw/obpinstall/obp/worklist/export_all_views_mapper.xml

	    EOH
	end
end
