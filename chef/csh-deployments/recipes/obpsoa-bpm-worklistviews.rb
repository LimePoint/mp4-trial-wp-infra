# Author: Jaya Sai Krishna Y

# Recipe to update worklist/BPM related configurations

environment_name = node.chef_environment.downcase
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../../csh-deployments/files/data_bags/#{environment_name}_dep_vars.json"))
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
my_topology_vars = my_dep_vars.merge(my_topology_vars)

password_vault_name = my_topology_vars['common']['password_vault_name']

asset_code = "obpsoa"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
userPassword = nil
userPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpsoa_admin").value)
release_version = my_topology_vars["#{asset_code}"]['release_version']
bpm_worklistviews_dir = "/oracle/app/binaries/obpsoa/fmw/obpinstall/BPM_WorklistViews"
artifactory_url = my_topology_vars['deployment']['CEMLI_ARTIFACTORY_URL']
releasePath = node['releasePath']!=nil ? node['releasePath'] : "au/com/westpac/csh/R16/release_23"
artifactVersion="CSH-OBP-release_23-014-00"
flexfieldsUrl="#{artifactory_url}/#{releasePath}/extensionssoaapp/#{artifactVersion}/extensionssoaapp-#{artifactVersion}.zip"
hostname=my_topology_vars["#{asset_code}"]['admin']['listen_address']
soa_hostname = my_topology_vars["#{asset_code}"]['soa_server']['listen_address']
soa_port = my_topology_vars["#{asset_code}"]['soa_server']['listen_port']
soaURLforSOAStatus="http://#{soa_hostname}:#{soa_port}/soa-infra/services/isSoaServerReady"
weblogicMgmtUrl="http://#{hostname}:17001/management/tenant-monitoring/servers"
puts "weblogic Management URL #{weblogicMgmtUrl} and obpsoa_admin password #{userPassword} and #{soaURLforSOAStatus}"
soaCompositeReadyStatus=%x(response=$(curl -k -s -o /dev/null -w "%{http_code}" #{soaURLforSOAStatus});echo $response)
userToUse=%x(response=$(curl -s -o /dev/null -u obpsoa_admin:#{userPassword} -w "%{http_code}" #{weblogicMgmtUrl});if [ "$response" == "200" ]; then echo "obpsoa_admin"; else echo "weblogic"; fi).chop

if userToUse.eql?("obpsoa_admin")
   userPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpoid/obpsoa_admin").value)
else
   userPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpsoa/weblogic").value)
end

puts "=========================================================================="
puts "Recipe is running to perform flexfields operations using user #{userToUse}"
puts "=========================================================================="
puts "SOA Server Composites readiness status is #{soaCompositeReadyStatus}"
puts "=========================================================================="

=begin
if node['mode'].eql?('test')
  puts "Inside first if block"
  artifactory_url=artifactory_url.sub("Snapshot","Verify")
  releasePath="au/com/westpac/csh/R16"
  artifactVersion="CSH-OBP-release_23-014-00"
  flexfieldsUrl="#{artifactory_url}/#{releasePath}/extensionssoaapp/#{artifactVersion}/extensionssoaapp-#{artifactVersion}.zip"
  puts "Flexfields ArtifactURL is #{flexfieldsUrl} "
  puts "Release version of OBP is #{release_version}"
  Chef::Log.info ("Flexfields ArtifactURL is #{flexfieldsUrl} ")
end
if node['artifactVersion']!=nil
  artifactVersion = node['artifactVersion']
  flexfieldsUrl="#{artifactory_url}/#{releasePath}/extensionssoaapp/#{artifactVersion}/extensionssoaapp-#{artifactVersion}.zip"
  puts "New Flexfields ArtifactURL is #{flexfieldsUrl} "
  Chef::Log.info ("New Flexfields ArtifactURL is #{flexfieldsUrl} ")
elsif artifactVersion==nil
  puts "Artifact Version is not set"
  Chef::Log.info ('Artifact Version is not set')
  return
end
  bash "Download and unzip BPMWorkListViews" do
  action:run
  code <<-EOH
    echo "Url is #{flexfieldsUrl}"
    status="#{soaCompositeReadyStatus}"
    if curl -k --output /dev/null --silent --head --fail "#{flexfieldsUrl}"; then
      echo "Artefact exists: #{flexfieldsUrl}"
      echo "Downloading Artefact ..."
      curl -k "#{flexfieldsUrl}" -o /tmp/bpmworklistviews.zip
    else
      echo "Artefact does not exist: $url"
      exit 1
    fi
    cd /oracle/app/binaries/obpsoa/fmw/obpinstall/;
    rm -rf BPM_WorklistViews
    cp -vf /tmp/bpmworklistviews.zip /oracle/app/binaries/obpsoa/fmw/obpinstall/;
    unzip bpmworklistviews.zip
    cp -rvf flexfield/* /oracle/app/binaries/obpsoa/fmw/obpinstall/

    counter=1

    while [ "$counter" -lt 1200 ] && [ "$status" != "200" ]; do
      counter=$(($counter+10))
      echo "Status of Soa Server is $status !! Waiting for 10 seconds"
      sleep 10
      status=$(curl -k -s -o /dev/null -w "%{http_code}" #{soaURLforSOAStatus})
    done
    if [ $status == "200" ]; then
      echo "Soa Server is up and running"
    else
      echo "Soa Server has been timeout"
    fi
    EOH
    Chef::Log.info('BPM_WorklistViews artifacts copied')
  end
=end
bash "Copy Downloaded BPMWorkListViews" do
  action:run
  code <<-EOH
  status="#{soaCompositeReadyStatus}"

    cd /oracle/app/binaries/obpsoa/fmw/obpinstall/;
    if [ ! -d "flexfield" ]; then
        echo "Flexfields directory seems not part of SOAApp Artifact"
        exit 1
    fi
    rm -rf BPM_WorklistViews
    cp -rvf flexfield/* /oracle/app/binaries/obpsoa/fmw/obpinstall/
    rm -rf flexfield/*
    counter=1

    while [ "$counter" -lt 1200 ] && [ "$status" != "200" ]; do
      counter=$(($counter+10))
      echo "Status of Soa Server is $status !! Waiting for 10 seconds"
      sleep 10
      status=$(curl -k -s -o /dev/null -w "%{http_code}" #{soaURLforSOAStatus})
    done
    if [ $status == "200" ]; then
      echo "Soa Server is up and running"
    else
      echo "Soa Server has been timeout"
    fi
    EOH
    Chef::Log.info('BPM_WorklistViews artifacts copied')
  end


bash 'Execute migrateWorklist-views-import.sh' do
  code <<-EOH
    cd #{bpm_worklistviews_dir};
    userName=#{userToUse}
    if [ "$userName" == "obpsoa_admin" ]; then
        echo "Inside IF block 1"
        sed -i 's/user.*weblogic/user = obpsoa_admin/g' migration-views.properties;
        sed -i 's/SOA_ADMIN_USER/obpsoa_admin/g' export_all_views.xml;
    fi
    export MW_HOME=/oracle/app/binaries/obpsoa/fmw;
  . /oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/commEnv.sh;
  ant -f /oracle/app/binaries/obpsoa/fmw/soa/bin/ant-t2p-worklist.xml -Dbea.home=/oracle/app/binaries/obpsoa/fmw -Dsoa.home=/oracle/app/binaries/obpsoa/fmw/soa -Dmigration.properties.file=#{bpm_worklistviews_dir}/migration-views.properties -Dsoa.hostname=#{soa_hostname} -Dsoa.rmi.port=#{soa_port} -Dsoa.admin.user=#{userToUse} -Dsoa.admin.password=#{userPassword} -Drealm=jazn.com -Dmigration.file=#{bpm_worklistviews_dir}/export_all_views.xml -Dmap.file=#{bpm_worklistviews_dir}/export_all_views_mapper.xml
    EOH
end

bash 'Execute Flexfields Update' do
  code <<-EOH
    cd #{bpm_worklistviews_dir};
    userName=#{userToUse}
    if [ "$userName" == "obpsoa_admin" ]; then
      sed -i 's/user.*weblogic/user = obpsoa_admin/g' migration-flexfields.properties;
    fi
    export MW_HOME=/oracle/app/binaries/obpsoa/fmw;
  . /oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/commEnv.sh;

  ant -f /oracle/app/binaries/obpsoa/fmw/soa/bin/ant-t2p-worklist.xml -Dbea.home=/oracle/app/binaries/obpsoa/fmw -Dsoa.home=/oracle/app/binaries/obpsoa/fmw/soa -Dmigration.properties.file=#{bpm_worklistviews_dir}/migration-flexfields.properties -Dsoa.hostname=#{soa_hostname} -Dsoa.rmi.port=#{soa_port} -Dsoa.admin.user=#{userToUse} -Dsoa.admin.password=#{userPassword} -Drealm=jazn.com -Dmigration.file=#{bpm_worklistviews_dir}/export_labels.xml -Dmap.file=#{bpm_worklistviews_dir}/export_taskDef_mapper.xml
    EOH
end