
# Recipe:: Copy TP jars
# Author: Harsha Gurram


environment_name = node.chef_environment.downcase
node_sn = node.name.split('.')[0].downcase
asset_code='obpsoa'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))
my_topology_vars = my_dep_vars.merge(my_topology_vars)
asset_vars = my_topology_vars[asset_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']
stage_dir = '/oracle/app/binaries/deployments/tp_jars'
target_dir = '/oracle/app/binaries/obpsoa/fmw/soa/soa/modules/chemistry-opencmis-client'
artifactory_url = my_topology_vars['deployment']['CEMLI_ARTIFACTORY_URL']


directory "#{stage_dir}" do
  owner "oracle"
  group "oinstall"
  mode 0755
  recursive true
  action :create
  not_if { ::Dir.exists?("#{stage_dir}") } 
end

bash "Back Up Existing artefacts" do
  code <<-EOH
    cd #{target_dir}/..
    cp -prv chemistry-opencmis-client chemistry-opencmis-client.bkp.orig
    rm -rvf #{target_dir}/*.jar
    EOH
  not_if { ::Dir.exists?("#{target_dir}/../chemistry-opencmis-client.bkp.orig") } 
end

  log "DOWNLOADING OPEN-CHEMISTRY JARS from artifactory - #{artifactory_url}"

remote_file "#{stage_dir}/open-chemistry-jars.zip" do
  source "#{artifactory_url}/au/com/westpac/csh/R12/ThirdPartJars/SOA/open-chemistry-jars.zip"
  owner 'oracle'
  group 'oinstall'
  mode '0755'
  action :create
end

log "Extracting ZIP for Jars"

bash "Extracting required jars" do
  code <<-EOH
    cd #{stage_dir}
    rm -rf open-chemistry-jars
    unzip open-chemistry-jars.zip
    chmod -R 755 *
    EOH
  only_if { ::File.exist?("#{stage_dir}/open-chemistry-jars.zip") }
end

log "Copying Jars"

bash "copy jars to #{target_dir}" do
  code <<-EOH
    cd #{stage_dir}/open-chemistry-jars
    rsync -avz *.jar #{target_dir}/
    EOH
end

