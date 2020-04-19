
# Recipe to get the status of servers and 

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_list = ['obpbip','obpsoa','obpobh','obpobu','obpdoc','obpipm','obpurm','obpiom','obpcim','obpodi','obpoid','obpcid','obposb']
#asset_code = "obp#{item_code}"

#if ['obpoid'].include?(asset_code)
#  asset_code = 'obpoim'
#elsif ['obpcid'].include?(asset_code)
#  asset_code = 'obpcim'
#end

asset_list.each do |asset_code|
domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"
base_dir = "/tmp"

template "Processing wlscheck.py" do
	source "fmw/wlst/wlscheck.py.erb"
	path "#{base_dir}/wlscheck.py"
	mode '0644'
	user 'oracle'
	group 'oinstall'
end

    bash 'Applying health check for #{asset_code}' do
      	code <<-EOH
          /oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh /oracle/stage/custom/csh/common/wlscheck.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl}
         EOH
    end
 end



