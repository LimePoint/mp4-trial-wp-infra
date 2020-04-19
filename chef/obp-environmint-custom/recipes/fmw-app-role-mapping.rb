# Author: Harsha Gurram
# Recipe to grant/revoke FMW Application Roles to User Groups

environment_name = node.chef_environment.downcase

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']

#Derive the asset name from the node name
item_code = node.name.split('.')[0][-5..-3].downcase
asset_code = "obp#{item_code}"
if asset_code == 'obpoid'
    asset_code = 'obpoim'
elsif asset_code == 'obpcid'
    asset_code = 'obpcim'
end

base_dir = "/tmp"

domain_name = my_topology_vars["#{asset_code}"]['wls_domain_name']
weblogicAdminPassword = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{password_vault_name}/#{asset_code}/weblogic").value)
weblogicAdminUrl = "t3://#{my_topology_vars["#{asset_code}"]['admin']['listen_address']}:#{my_topology_vars["#{asset_code}"]['admin']['listen_port']}"

template "Processing fmw-app-role-mapping.py" do
	source "fmw/wlst/fmw-app-role-mapping.py.erb"
	path "#{base_dir}/fmw-app-role-mapping.py"
	mode '0644'
	user 'oracle'
	group 'oinstall'
end	

if asset_code == 'obpsoa'
	arguments=['soa-infra obpsoa_administrators SOAOperator:SOAAuditAdmin:BPMWorkflowAdmin:MiddlewareAdministrator:BPMAGAdmin grant','soa-infra obpsoa_administrators:OBP-TechSupportL2 SOAAdmin grant','soa-infra Monitors SOAMonitor grant','soa-infra OBP-Configurator:OBP-TechSupportL2 SOADesigner grant','BamServer obpsoa_administrators BAMAdministrator:BAMContentCreator grant','BamServer BAM_EDITOR BAMArchitect:BAMContentCreator:IInsightContentCreator grant','BamServer BAM_CreditOpsManager:BAM_OtherManager:BAM_HOSOpsManager:BAM_SalesOpsManager:BAM_MortgageOriginationsGroupManager BAMContentViewer:BPMContentViewer:IInsightContentViewer grant','BamServer BAM_PricingOpsManager BAMContentViewer:BPMContentViewer:IInsightContentViewer revoke']
elsif asset_code == 'obpbip'
	arguments=['obi obpbip_administrators:BIAdministrator BIServiceAdministrator grant','obi BIConsumer BIConsumer grant','obi BIAuthor BIContentAuthor grant']
elsif ['obpoim','obpcim','obpdoc'].include?(asset_code)
	arguments=['soa-infra Monitors SOAMonitor grant']
end

arguments.each do |args|
	bash 'Executing fmw-app-role-mapping.py' do
  		code <<-EOH
  		echo "#{args}"
    	/oracle/app/binaries/#{asset_code}/fmw/oracle_common/common/bin/wlst.sh #{base_dir}/fmw-app-role-mapping.py weblogic #{weblogicAdminPassword} #{weblogicAdminUrl} #{args}
    	if [ $? -eq 1 ]; then echo "App Role Mapping Failed";exit 1;fi
    	EOH
	end
end