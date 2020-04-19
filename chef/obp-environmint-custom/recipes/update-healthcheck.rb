
# Recipe to Update the HealthCheck Location

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

if ['obpoid'].include?(asset_code)
  asset_code = 'obpoim'
elsif ['obpcid'].include?(asset_code)
  asset_code = 'obpcim'
end

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"



  bash 'Copy HelathCheck war from stage to domain_home' do
    code <<-EOH
      cp -p /oracle/stage/custom/csh/common/HealthCheck.war /oracle/app/runtime/#{asset_code}/domains/applications/#{domain_name}/
      EOH
    not_if { ::File.exist?("/oracle/app/runtime/#{asset_code}/domains/applications/#{domain_name}/HealthCheck.war") }
    Chef::Log.info('HealthCheck.war copied to the domain location.')
  end

clusterMap = get_all_clusters(asset_code,my_topology_vars["#{asset_code}"])

  if ['obpoim','obpcim','obpoam','obpipm','obpurm'].include?(asset_code)
    bash 'Applying health check for #{asset_code}' do
      code <<-EOH
        /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/stage/custom/csh/common/deleteHealthCheck.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} HealthCheck /oracle/app/runtime/#{asset_code}/domains/applications/#{domain_name}/HealthCheck.war #{clusterMap.values.join(",")} nostage 650
        /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/stage/custom/csh/common/deployApplication.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} HealthCheck /oracle/app/runtime/#{asset_code}/domains/applications/#{domain_name}/HealthCheck.war #{clusterMap.values.join(",")} nostage 650
        EOH
    end
  else
    bash "Applying HealthCheck from domain location" do
      code <<-EOH
        /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/stage/custom/csh/common/updateHealthCheck.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} HealthCheck /oracle/app/runtime/#{asset_code}/domains/applications/#{domain_name}/HealthCheck.war #{clusterMap.values.join(",")} nostage 650
        EOH
    end
  end


