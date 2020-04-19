
# Recipe:: obp-files-healthcheck
# To configure custom obp-files vip health check
# Author: Harsha Gurram


environment_name = node.chef_environment.downcase
node_sn = node.name.split('.')[0].downcase
asset_code='obpipm'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
asset_vars = my_topology_vars[asset_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']
as_domain_home = '/oracle/app/runtime/obpipm/domains/obpipm_domain'
ms_domain_home = '/oracle/app/binaries/runtime/obpipm/domains/obpipm_domain'
intradoc_dir = "/oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/"
#weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)


bash "Deploying Component" do
  code <<-EOH
    if grep "ComponentName\=CSHOWCUtils" #{intradoc_dir}/custom/CSHOWCUtils/manifest.hda; then 
      echo "Health Check Component already deployed... SKIPPING"
    else
      cd /oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/ucm/cs/bin
      ./ComponentTool -v --install /oracle/stage/custom/csh/obpipm/CSHOWCUtils.zip
      echo "Health Check Component successfully deployed..."
    fi
    EOH
end

bash "Updating webmap.hda" do
  code <<-EOH
    if grep "IS_CSH_NETAPP_AVAILABLE" #{intradoc_dir}/data/webmap/webmap.hda; then 
      echo "Update to webmap.hda exists... SKIPPING"
    else
      echo "Updating file webmap.hda"
      tac #{intradoc_dir}/data/webmap/webmap.hda | awk 'NR==1,/@end/{sub(/@end/, "@end\\nWebUrlMapPlugin\\n<!--$cgipath-->?IdcService=IS_CSH_NETAPP_AVAILABLE\\&coreContentOnly=1\\nsuffix\\ncs/checkucm.html")} 1' | tac > /oracle/app/binaries/obpipm/tmp/webmap.hda.tmp
      sed -i 's/IS_CSH_NETAPP_AVAILABLE@endcoreContentOnly/IS_CSH_NETAPP_AVAILABLE\\&coreContentOnly/' /oracle/app/binaries/obpipm/tmp/webmap.hda.tmp
      cp /oracle/app/binaries/obpipm/tmp/webmap.hda.tmp #{intradoc_dir}/data/webmap/webmap.hda
      echo "Updated webmap.hda successfully. Restart UCM Server."
    fi
    EOH
end



