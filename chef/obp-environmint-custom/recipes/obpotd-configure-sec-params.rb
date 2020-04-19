# Author: Harsha Gurram

# Recipe to configure Security Parameters on OTD VIPS


environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

serverConfigDirs = [ "/oracle/app/instances/obpotd/domains/obpotd_domain/config/fmwconfig/components/OTD/instances","/oracle/app/runtime/obpotd/domains/obpotd_domain/config/fmwconfig/components/OTD" ]


serverConfigDirs.each do |config_dir|
    bash 'Update security params in obj.conf file' do
      code <<-EOH
      cd #{config_dir};
      for i in $(find . -type f -name *server-obj.conf);do
        echo "Inspecting $i"
        if grep 'Strict-Transport-Security' $i; then
          echo 'HSTS Params exist..SKIPPING'
        else
          echo 'HSTS Params not found ..UPDATING'
          sed -i "/fn=\\"map\\"/a <If \\$uri =~ \\"^/favicon.ico\\">\\nNameTrans fn=\\"set-variable\\" error=\\"404\\"\\n</If>\\nObjectType fn=\\"block-proxy-agent\\"\\nOutput fn=\\"set-variable\\" insert-srvhdrs=\\"Strict-Transport-Security: max-age=7776000;  includeSubdomains\\"" $i
        fi
      done
      EOH
    end
end
