# Author: Jaya Sai Krishna Y

# Recipe for deployment customisations this also contain latest changes for 1.7 Business config and new tokens for ODI CWallet

environment_name = node.chef_environment.downcase
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../../csh-deployments/files/data_bags/#{environment_name}_dep_vars.json"))
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
my_topology_vars = my_dep_vars.merge(my_topology_vars)
password_vault_name = my_topology_vars['common']['password_vault_name']
obpEXTAPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpbip/OBPBIP").value)
obpHostPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpobh/OBPHOST").value)
obpHostDBUrl="#{my_topology_vars['obpobh']['database']['scan_address']}:#{my_topology_vars['obpobh']['database']['listen_port']}/#{my_topology_vars['obpobh']['database']['service_name']}"
cwalletpassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/deployment/cwalletpassword").value)
if (@environment_name =~ /^svp\d*w/ or @environment_name =~ /^prd\d*w/) then
  obpHostDBUrl="#{my_topology_vars['obpobh']['database']['secondary_scan_address']}:#{my_topology_vars['obpobh']['database']['listen_port']}/#{my_topology_vars['obpobh']['database']['service_name']}"
end
obphostSSLURL="http://#{my_topology_vars['obpobh']['obphost_server']['listen_address']}#{my_topology_vars['obpobh']['dns_domain_name']}:#{my_topology_vars['obpobh']['obphost_server']['listen_port']}"

item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"
node_sn = node.name.split('.')[0].
downcase

obaDBUrl = my_topology_vars['obpobh']['database']['sysconfig_url'].gsub("OBP_PRIM","OBA_PRIM")
release_version = my_topology_vars["#{asset_code}"]['release_version']

if "#{node_sn}".include?("obh01") and !"#{release_version}".include?("2.6") then
   puts "Release Version of #{asset_code} is #{release_version}"
   if File.file?("/oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config/deploy.properties") then
     execute_cmd=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep skipRegex;echo "=============================";echo "";sed -i "s~{SKIP.REGEX}~.*OBP262.*~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep skipRegex;echo "=============================")
      puts execute_cmd
      cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep OBP_DB_READONLY_PASSWORD;echo "=============================";echo "";sed -i "s~{OBPDB.READONLY.PASSWORD}~#{obpHostPassword}~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep OBP_DB_READONLY_PASSWORD;echo "=============================")
     puts cmd_output
     cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep OBP_DB_URL;echo "=============================";echo "";sed -i "s~{OBPDB.URL}~#{obpHostDBUrl}~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep OBP_DB_URL;echo "=============================")
     puts cmd_output
     cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep OBP_DB_READONLY_USERID;echo "=============================";echo "";sed -i "s~{OBPDB.READONLY.USERNAME}~OBPHOST_OBP~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep OBP_DB_READONLY_USERID;echo "=============================")
     puts cmd_output
     cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep common_host_endpoint;echo "=============================";echo "";sed -i "s~{OBPHOST.SSL.ENDPOINT}~#{obphostSSLURL}~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep common_host_endpoint;echo "=============================")
     puts cmd_output
     cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep jks_password;echo "=============================";echo "";sed -i "s~{JKS.PASSPHRASE}~#{cwalletpassword}~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep jks_password;echo "=============================")
     puts cmd_output
     cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/deploy/host_db/config;cat deploy.properties | grep key_password;echo "=============================";echo "";sed -i "s~{KEY.PASSPHRASE}~#{cwalletpassword}~g" deploy.properties;echo "=============================";echo "After replacing Regex";cat deploy.properties | grep key_password;echo "=============================")
     puts cmd_output
     cmd_output=%x(echo "=============================";echo "Before replacing Regex";cd /oracle/app/binaries/deployments/hostdb/host_db/common/all_group/scripts;cat generateCwallet.sh | grep FMW_HOME=;echo "=============================";echo "";sed -i "s~\\\$FMW_DIR~/oracle/app/binaries/obpobh/fmw~g" generateCwallet.sh;echo "=============================";echo "After replacing Regex";cat generateCwallet.sh | grep FMW_HOME=;echo "=============================")
     puts cmd_output
   end
end

if "#{node_sn}".include?("odi0") then
     encryptedODIOBAPassword=%x(/oracle/app/runtime/obpodi/domains/obpodi_domain/bin/encode.sh -INSTANCE=OracleDISAgent1 #{obpEXTAPassword} | grep -v NOTIFICATION).chop

     cmd_output=%x(for i in `ls -d /oracle/app/binaries/deployments/mintdeploy/obpProductDeploy/odiExpress/topologyFolder/topology/*/*.xml`;do for l in `grep -irl "{OBPA_EXT_DS_USERNAME}" $i`;do echo "Updating OBPA_EXT_DS_USERNAME token in the files $l"; echo "Before applying customisations file contents"; cat $l ;sed -i "s|{OBPA_EXT_DS_USERNAME}|OBPA_EXT|g" $l;echo "Updating OBPA_EXT_DS.OBPA_EXT encrypted Password in $l";sed -i 's|"Pass" type="java.lang.String">null|"Pass" type="java.lang.String">#{encryptedODIOBAPassword}|g' $l ; echo "After applying customisations"; cat $l; echo "Update done";done;done)
     puts cmd_output
     cmd_output=%x(for i in `ls -d /oracle/app/binaries/deployments/mintdeploy/obpProductDeploy/odiExpress/topologyFolder/topology/*/*.xml`;do for l in `grep -irl "{OBPA_EXT_DS_DRIVER}" $i`;do echo "Updating OBPA_EXT_DS_DRIVER token in the files $l"; echo "Before applying customisations file contents"; cat $l ;sed -i "s|{OBPA_EXT_DS_DRIVER}|oracle.jdbc.OracleDriver|g" $l ; echo "After applying customisations"; cat $l ; echo "Update done";done;done)
     puts cmd_output
     cmd_output=%x(for i in `ls -d /oracle/app/binaries/deployments/mintdeploy/obpProductDeploy/odiExpress/topologyFolder/topology/*/*.xml`;do for l in `grep -irl "{OBPA_EXT_DS_URL}" $i`;do echo "Updating OBPA_EXT_DS_URL token in the files $l"; echo "Before applying customisations file contents"; cat $l ;sed -i "s|{OBPA_EXT_DS_URL}|#{obaDBUrl}|g" $l; echo "After applying customisations"; cat $l ; echo "Update done";done;done)
     puts cmd_output

     puts "OBPAEXT encrypted password is #{encryptedODIOBAPassword}"

end

