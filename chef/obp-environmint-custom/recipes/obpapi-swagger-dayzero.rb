#Author JSKY
require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../../csh-deployments/files/data_bags/#{environment_name}_dep_vars.json"))
my_topology_vars = my_dep_vars.merge(my_topology_vars)
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"
node_sn = node.name.split('.')[0].downcase

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:17001"
obphost_nonssl_host = "#{my_topology_vars["#{asset_code}"]['obphost_server']['listen_address']}#{my_topology_vars["#{asset_code}"]['dns_domain_name']}"
obphost_nonssl_port = "#{my_topology_vars["#{asset_code}"]['obphost_server']['listen_port']}"
release_version = my_topology_vars["#{asset_code}"]['release_version']
artifactory_url = my_topology_vars['deployment']['CEMLI_ARTIFACTORY_URL']
hostname = "#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}"
portnum = "#{my_topology_vars["#{asset_code}"]['admin']['port']}"
swagger_src = "/oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/output/swagger.json"
swagger_yaml = "/oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/OBPAPI/yaml"
releasePath = node['releasePath']!=nil ? node['releasePath'] : "au/com/westpac/csh/R15"
obpapiurl= node['versionNum']!=nil ? "#{artifactory_url}/#{releasePath}/extensionobpapi/#{node['versionNum']}/extensionobpapi-#{node['versionNum']}.zip" : abort
obphost_otd_host=""
if node_sn.include?("svp") or node_sn.include?("prd") then
obphost_otd_host = node_sn.split('.')[0][-13..-11]+node_sn.split('.')[0][-9..-7]+"api"+"#{my_topology_vars["#{asset_code}"]['dns_domain_name']}"
else
obphost_otd_host = node_sn.split('.')[0][-13..-11]+node_sn.split('.')[0][-9..-6]+"api"+"#{my_topology_vars["#{asset_code}"]['dns_domain_name']}"
end

puts "OBPAPI GENERATED Host Name == #{obphost_otd_host}"
Chef::Log.info("Testing Swagger input #{releasePath}")
#if release_version != '2.6.2'
#  Chef::Log.info ('Doesnt Apply to this Release, check the release_version in env_vars')
#  return
#end
if ("#{node_sn}".include?("obh01")) then
  bash "run swagger part 1" do
  action:run
  code <<-EOH
    url=#{obpapiurl}
    if curl -k --output /dev/null --silent --head --fail "$url"; then
      echo "Artefact exists: $url"
      echo "Downloading Artefact ..."
      curl -k "$url" -o /tmp/obpapi.zip
    else
      echo "Artefact does not exist: $url"
      exit 1
    fi

    mkdir -p /tmp/obpapizip
    cd /oracle/app/binaries/#{asset_code}/fmw/obpinstall/
    rm -rf OBPAPI
    echo "Unzip OBPAPI.zip"
    unzip -oq /tmp/obpapi.zip
    echo "Unzip of OBPAPI done"
    mkdir -p /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/output
    mkdir -p /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/resources
    rm -f /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/output/swagger.json
    cp -r /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp_bkp
    cp -r /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/binaries/*.jar /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/
    if [ -f /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/org.metaborg.sunshine2-2.4.1.jar ]; then
      mv /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/org.metaborg.sunshine2-2.4.1.jar /tmp/obpapizip/
    fi
    cp /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/binaries/guava-20.0.jar /oracle/app/binaries/#{asset_code}/fmw/wlserver/modules
    cp /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/binaries/com.google.guava.guava.jar /oracle/app/binaries/#{asset_code}/fmw/wlserver/modules
    sed -i "s~^adminPassword=.*$~adminPassword=#{weblogicAdminPassword}~g;s~^javaHome=.*$~javaHome=/oracle/app/binaries/java8~g;s~^obp_host=.*$~obp_host=#{obphost_nonssl_host}~g;s~^obp_port=.*$~obp_port=#{obphost_nonssl_port}~g;s~^swagger_src=.*$~swagger_src=#{swagger_src}~g;s~^swagger_dest=.*$~swagger_dest=#{swagger_yaml}~g;" /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/process_swagger_v2.sh
  EOH
  end

  Chef::Log.info("WeblogicHost: #{weblogicAdminUrl}")
  Chef::Log.info("weblogicAdminPassword: #{weblogicAdminPassword}")

  Chef::Log.info("Creating WLST ")

  template 'shutdown-obpobh-managed.py.erb' do
    source "fmw/2.6.2/shutdown-#{asset_code}-managed.py.erb"
    path "/oracle/app/binaries/tmp/shutdown-#{asset_code}-managed.py"
    mode '0700'
  end

  bash 'Shutting down obphost managed server' do
    code <<-EOH
      /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/shutdown-#{asset_code}-managed.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
      cd /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/servers
      for i in `ls -d obphost_server*`;do rm -rf $i/tmp; rm -rf $i/cache; rm -rf $i/stage;done;
    EOH
  end

  template 'start-obpobh-managed.py.erb' do
    source "fmw/2.6.2/start-#{asset_code}-managed.py.erb"
    path "/oracle/app/binaries/tmp/start-#{asset_code}-managed.py"
    mode '0700'
  end

  bash 'Starting obphost managed server' do
    code <<-EOH
      /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/start-#{asset_code}-managed.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
  end

  bash "run swagger part 2" do
    action:run
    code <<-EOH

    cd /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI
    chmod 755 process_swagger_v2.sh
    ./process_swagger_v2.sh
    if [ $? -eq 1 ]; then
        echo "Swagger Initialisation Failed"
        mv /tmp/obpapizip/org.metaborg.sunshine2-2.4.1.jar /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/org.metaborg.sunshine2-2.4.1.jar
        rm -rf /oracle/app/logs/obpobh/OBPAPI/yaml/
        exit 1
    fi
    rm -rf /oracle/app/logs/obpobh/OBPAPI/yaml/
    mkdir -p /oracle/app/logs/obpobh/OBPAPI/yaml/
    cd /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/OBPAPI/yaml/
    for i in `find . -name "*.yaml"`;do sed -i "s~http://#{obphost_nonssl_host}:#{obphost_nonssl_port}~https://#{obphost_otd_host}~g" $i;done
    cp -rf /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/OBPAPI/yaml/* /oracle/app/logs/obpobh/OBPAPI/yaml/
    ls -ltrc /oracle/app/logs/obpobh/OBPAPI/yaml/
    touch /oracle/app/logs/obpobh/OBPAPI/process_swagger.data
    cd /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib
    rm jackson-dataformat-yaml-2.9.6.jar jersey-media-json-jackson-2.26.jar reflections-0.9.11.jar mimepull-1.9.6.jar guava-20.0.jar jersey-media-multipart-2.25.1.jar snakeyaml-1.18.jar
    if [ -f /tmp/obpapizip/org.metaborg.sunshine2-2.4.1.jar ]; then
        cp /tmp/obpapizip/org.metaborg.sunshine2-2.4.1.jar /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/org.metaborg.sunshine2-2.4.1.jar
    fi

  EOH
  end


  bash 'Shutting down obphost managed server' do
    code <<-EOH
      /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/shutdown-#{asset_code}-managed.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
      cd /oracle/app/runtime/#{asset_code}/domains/#{domain_name}/servers
      for i in `ls -d obphost_server*`;do rm -rf $i/tmp; rm -rf $i/cache; rm -rf $i/stage;done;
    EOH
  end

  bash 'Starting obphost managed server' do
    code <<-EOH
      /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/start-#{asset_code}-managed.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
  end

  template 'deploy-obpapi-swagger.py.erb' do
    source "fmw/2.6.2/deploy-obpapi-swagger.py.erb"
    path "/oracle/app/binaries/tmp/deploy-obpapi-swagger.py"
    mode '0700'
  end

  bash 'Deploying OBPAPI' do
    code <<-EOH
      /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/app/binaries/tmp/deploy-obpapi-swagger.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
    EOH
  end
end

if ("#{my_topology_vars["#{asset_code}"]['hostnameList'][1]}" != nil) and (!"#{node_sn}".include?("obh01")) then

  count=0
  while count<=2400 and !File.exist?("/oracle/app/logs/obpobh/OBPAPI/process_swagger.data")
     puts "Process swagger execute is still in progress, Secs passed since first check #{count}"
     sleep(60)
     count+=60
  end

  bash "run swagger on remaining nodes" do
  code <<-EOH
    url=#{artifactory_url}/#{releasePath}/OBPAPI.zip
    if curl -k --output /dev/null --silent --head --fail "$url"; then
      echo "Artefact exists: $url"
      echo "Downloading Artefact ..."
      curl -k "$url" -o /tmp/obpapi.zip
    else
      echo "Artefact does not exist: $url"
      exit 1
    fi

    mkdir -p /tmp/obpapizip
    cd /oracle/app/binaries/#{asset_code}/fmw/obpinstall/
    rm -rf OBPAPI
    echo "Unzip OBPAPI.zip"
    unzip -oq /tmp/obpapi.zip
    echo "Unzip of OBPAPI done"
    mkdir -p /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/output
    mkdir -p /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/resources
    rm -f /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/output/swagger.json
    cp -r /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp_bkp
    cp -r /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/binaries/*.jar /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/
    if [ -f /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/org.metaborg.sunshine2-2.4.1.jar ]; then
      mv /oracle/app/binaries/#{asset_code}/fmw/obpinstall/obp/ob.host.app/ob.app.host.tp/APP-INF/lib/org.metaborg.sunshine2-2.4.1.jar /tmp/obpapizip/
    fi
    cp /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/binaries/guava-20.0.jar /oracle/app/binaries/#{asset_code}/fmw/wlserver/modules
    cp /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/binaries/com.google.guava.guava.jar /oracle/app/binaries/#{asset_code}/fmw/wlserver/modules
    sed -i "s~^adminPassword=.*$~adminPassword=#{weblogicAdminPassword}~g;s~^javaHome=.*$~javaHome=/oracle/app/binaries/java8~g;s~^obp_host=.*$~obp_host=#{obphost_nonssl_host}~g;s~^obp_port=.*$~obp_port=#{obphost_nonssl_port}~g;s~^swagger_src=.*$~swagger_src=#{swagger_src}~g;s~^swagger_dest=.*$~swagger_dest=#{swagger_yaml}~g;" /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/process_swagger_v2.sh
    rm -rf /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/OBPAPI/yaml/
  EOH
  end


 bash 'Copying YAML from shared Directory from Node 1 to other nodes' do
    code <<-EOH
      cat /oracle/app/logs/obpobh/OBPAPI/process_swagger.data
      if [ $? -eq 1 ]; then
        echo "Could not find /oracle/app/logs/obpobh/OBPAPI/#{node_sn} even after 40 mins or There was error occurred during execution of Process_swagger.sh, check the node1 execution logs!!!!exiting..."
        exit 1
      fi
      mkdir -p /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/OBPAPI/yaml/
      cp -rf /oracle/app/logs/obpobh/OBPAPI/yaml/* /oracle/app/binaries/#{asset_code}/fmw/obpinstall/OBPAPI/OBPAPI/yaml/
      rm /oracle/app/logs/obpobh/OBPAPI/process_swagger.data
    EOH
  end

end