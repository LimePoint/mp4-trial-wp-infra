# Recipe: Recipe to complete post bundle patch steps for OIM and CIM 12c. 

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"

if my_topology_vars["#{asset_code}"]['dns_domain_name'] != '.wpdev.mintpress.io' && !['svp3r','prd3r','psp3'].include?(environment_name) && ['obpoid','obpcid'].include?(asset_code)
  if asset_code == 'obpoid'
    asset_code = 'obpoim'
  end
  if asset_code == 'obpcid'
    asset_code = 'obpcim'
  end
end


domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
managed_domain_home = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}"
fmw_home = "/oracle/app/binaries/#{asset_code}/fmw"
java_home = "/oracle/app/binaries/#{asset_code}/java"

weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
admin_listen_address = "#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}#{my_topology_vars["#{asset_code}"]['dns_domain_name']}"
schema_prefix = "#{my_topology_vars["#{asset_code}"]['database']['rcu_schema_prefix'].upcase}"
schema_password = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/#{asset_code.upcase}-MDS").value)
db_listen_address = "#{my_topology_vars["#{asset_code}"]['database']['scan_address']}"
db_service_name = "#{my_topology_vars["#{asset_code}"]['database']['service_name']}"
db_port = "#{my_topology_vars["#{asset_code}"]['database']['listen_port']}"


execute "backup profile template" do
	action :nothing
	command "cp #{fmw_home}/idm/server/bin/patch_oim_wls.profile #{fmw_home}/idm/server/bin/patch_oim_wls.profile.mint"
	cwd "#{fmw_home}/idm/server/bin"
	only_if { File.exists?("#{fmw_home}/idm/server/bin/patch_oim_wls.profile") }
	not_if { File.exists?("#{fmw_home}/idm/server/bin/patch_oim_wls.profile.mint") }
end


template "Processing update_patch_oim12c_wls_profile.erb" do
	source "fmw/oim/patch_oim12c_wls.profile.erb"
	path "#{fmw_home}/idm/server/bin/patch_oim_wls.profile"
	variables(
		:asset_code => asset_code,
		:fmw_home => fmw_home,
		:domain_home => managed_domain_home,
		:weblogic_pwd => weblogicAdminPassword,
		:admin_listen_address => admin_listen_address,
	    :schema_prefix => schema_prefix,
	    :schema_pwd => schema_password,
	    :db_listen_address => db_listen_address,
	    :db_service_name => db_service_name,
	    :db_port => db_port
	)
	mode '0644'
	user 'oracle'
	group 'oinstall'
	notifies :run, 'execute[backup profile template]', :before
	notifies :run, 'execute[Run patch_oim_wls Script]', :immediately
end


execute "Run patch_oim_wls Script" do
	action :nothing
	command "export PATH=#{java_home}/bin:$PATH; sh patch_oim_wls.sh"
	cwd "#{fmw_home}/idm/server/bin"
	puts "Post Bundle Patch Script patch_oim_wls has been executed.\nCheck #{fmw_home}/idm/server/bin/patch_oim_wls.log for any errors...."
	only_if { File.exists?("#{fmw_home}/idm/server/bin/patch_oim_wls.profile") }
	notifies :run, 'execute[Remove Identity Self Service Deployment]', :immediately
end


execute "Remove Identity Self Service Deployment" do
	action :nothing
	command "rm -rf #{managed_domain_home}/servers/oim_server1/tmp/_WL_user/oracle.iam.console.identity.self-service.ear_V2.0"
	cwd "#{managed_domain_home}"
	puts "Removed Identity Self Service Deployment"
	only_if { File.exists?("#{managed_domain_home}/servers/oim_server1/tmp/_WL_user/oracle.iam.console.identity.self-service.ear_V2.0") }
	notifies :run, 'ruby_block[Next Steps]', :immediately
end


ruby_block "Next Steps" do
	action :nothing
    block do
    	Chef::Log.info("\n")
    	Chef::Log.info("=================================")
    	Chef::Log.info("Post Patching Steps have run successfully for domain #{domain_name}.")
    	Chef::Log.info("Restart all servers in domain to complete the patching process.")
    	Chef::Log.info("=================================\n")
    end
end
