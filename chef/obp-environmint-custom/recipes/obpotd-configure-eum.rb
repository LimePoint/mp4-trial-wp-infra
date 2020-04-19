# Author: Harsha Gurram

# Recipe to configure EUM


environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

beacon_url = my_topology_vars['common']['appd_url']
eum_key = my_topology_vars['common']['eum_key']
username = "oracle"
groupname = "oinstall"
#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

hosting_dir = '/oracle/app/runtime/obpotd/domains/hosting'

cookbook_file "/oracle/app/binaries/obpotd/tmp/awk-script.sh" do
  source 'otd_eum/awk-script.sh'
  owner "#{username}"
  group "#{groupname}"
  mode '0750'
  action :create
end

serverConfigDirs = [ "/oracle/app/instances/obpotd/domains/obpotd_domain/config/fmwconfig/components/OTD/instances","/oracle/app/runtime/obpotd/domains/obpotd_domain/config/fmwconfig/components/OTD" ]

# Configure EUM 

friendly_vip_dirs = ['obp-banker','obp-worklist']
friendly_vip_dirs.each do |dir|
	vip_name = my_topology_vars['obpotd']['otd_config']["#{dir}"]['server_name']
	directory "#{hosting_dir}/#{dir}" do
		owner "oracle"
		group "oinstall"
		mode 0750
		recursive true
		action :create
		not_if { ::Dir.exists?("#{hosting_dir}/#{dir}") } 
	end

	cookbook_file "#{hosting_dir}/#{dir}/adrum-ext.js" do
      source 'otd_eum/adrum-ext.js'
      owner "#{username}"
      group "#{groupname}"
      mode '0750'
      action :create
    end

  cookbook_file "#{hosting_dir}/#{dir}/adrum-latest.js" do
    source 'otd_eum/adrum-latest.js'
    owner "#{username}"
    group "#{groupname}"
    mode '0750'
    action :create
  end

  cookbook_file "#{hosting_dir}/#{dir}/adrum-xd.html" do
    source 'otd_eum/adrum-xd.html'
    owner "#{username}"
    group "#{groupname}"
    mode '0750'
    action :create
  end

  template "#{hosting_dir}/#{dir}/adrum-wrapper.js" do
    source "adrum-wrapper.js.erb"
    owner "#{username}"
    group "#{groupname}"
    variables(
      :eum_key => "#{eum_key}",
      :friendly_vip => "#{vip_name}",
      :beacon_url => "#{beacon_url}"
    )
    mode '0750'
  end

  serverConfigDirs.each do |config_dir|
    bash 'Update eum config in obj.conf file' do
      code <<-EOH
      sh /oracle/app/binaries/obpotd/tmp/awk-script.sh #{config_dir} #{dir} configure
      EOH
    end
  end
end

# Disable EUM Config

disable_friendly_vip_dirs = ['obp-files','obp-reports','obp-sso']

disable_friendly_vip_dirs.each do |dir|

  serverConfigDirs.each do |config_dir|
    bash 'Disable eum config in obj.conf file' do
      code <<-EOH
      sh /oracle/app/binaries/obpotd/tmp/awk-script.sh #{config_dir} #{dir} disable
      EOH
    end
  end

end