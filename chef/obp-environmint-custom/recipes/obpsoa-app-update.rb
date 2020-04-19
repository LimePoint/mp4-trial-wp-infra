# Author: Harsha Gurram

# Recipe to update SOA-INFRA Deployment Plan

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

asset_code = "obpsoa"

obpsoa_wlsPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/obpsoa/weblogic").value)


bash 'Copy artefacts to server' do
  code <<-EOH
    rsync -av /oracle/stage/custom/csh/obpsoa/soainfraPlan_v2.xml /oracle/app/runtime/obpsoa/domains/obpsoa_domain/soainfraPlan_v2.xml
    EOH
  Chef::Log.info('Deployment Plan copied')
end
	
Chef::Log.info('Executing WLST to update Deployment plan of soa-infra')

bash 'Execute WLST ' do
  code <<-EOH
  	/oracle/app/binaries/obpsoa/fmw/oracle_common/common/bin/wlst.sh /oracle/stage/custom/csh/common/updateApplication.py weblogic #{obpsoa_wlsPassword} t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']} soa-infra /oracle/app/runtime/obpsoa/domains/obpsoa_domain/soainfraPlan_v2.xml
    EOH
end
