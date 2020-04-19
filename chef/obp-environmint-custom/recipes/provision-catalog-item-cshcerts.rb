require 'tempfile'
require 'base64'
require 'net/sftp'
require 'net/ssh'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

tenant = "csh"

_item_code="#{tenant.upcase}CERTS"

return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')


##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####
#

#########
Chef::Log.info("ENV: #{environment_name}")

global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.merge(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)

action = node.run_state['mintpress_action']

source_input_asset_list = ["all","*","obpotd", "obpcid", "obpdoc", "obpipm", "obpoam", "obpobh", "obpobu", "obpodi", "obpoid", "obpoim", "obposb", "obpsoa", "obpbip", "obpcim", "obpurm", "obp-banker", "obp-files", "obp-reports", "obp-records", "obp-worklist", "obp-sso","obpapi"]

source_asset_list = ["obpotd", "obpcid", "obpdoc", "obpipm", "obpoam", "obpobh", "obpobu", "obpodi", "obpoid", "obpoim", "obposb", "obpsoa", "obpbip", "obpcim", "obpurm", "obp-banker", "obp-files", "obp-reports", "obp-records", "obp-worklist", "obp-sso","obpapi"]


cert_asset_list = Array.new

override_asset_list = my_topology_vars["#{tenant}certs"]['override_asset_list']

archive_dir_name = Time.now.strftime('%Y%m%d_%H%M%S')

Chef::Log.info("OVERRIDE LIST : #{override_asset_list}") 

## Construct Asset List based on Input ##
if override_asset_list != ''
  csv_of_assets=override_asset_list.split(',')
  unless (csv_of_assets-source_input_asset_list).empty?
   raise "INCORRECT ASSET CODE SPECIFIED. RECHECK THE INPUT - #{csv_of_assets-source_input_asset_list}"
  end
  cert_asset_list = (override_asset_list == '*' || override_asset_list.downcase == 'all') ? source_asset_list : csv_of_assets
elsif my_topology_vars.key?'include'
  source_asset_list.each  do |item|
      if my_topology_vars['include'].key?(item) && my_topology_vars['include'][item].downcase == 'true'
          cert_asset_list << "#{item}"
      end
  end
end

Chef::Log.info("PERFORMING CERT RELATED ACTION ON ASSETS : #{cert_asset_list}")
############
errmsg = ["Compile Error","Error executing action","ShellCommandFailed","FATAL: Stacktrace dumped"]

template "Processing cert-build-params.json" do
  source "default/build-params.json.erb"
  path "/tmp/#{tenant}-#{environment_name}-cert-build.json"
  variables(
    :env_name => environment_name,
    :asset_list => cert_asset_list,
    :mm_action => "NA"
  )
  mode '0644'
end

def updateWLSCert(host,errmsg)
  begin
    Chef::Log.info("Updating WLS Cert in #{host} ..")
    ssh_keyfile = "/home/mintpress/mintpress/.ssh/id_rsa"
    Chef::Log.info("Starting Upload of asset attribute to #{host} ..")
    Net::SFTP.start(host, "mintpress", :keys => [ssh_keyfile], :paranoid => Net::SSH::Verifiers::Null.new) do |sftp|
      sftp.file.open("/tmp/renew_asset.json", "w") do |f|
        f.puts "{\"renew_asset\":\"#{host}\"}"
      end
    end
    Chef::Log.info("Finished Upload of asset attribute to #{host} ..")
    Chef::Log.info("Starting Executing update-wls-cert recipe on target node #{host} ..")
    Net::SSH.start(host, "mintpress", :keys => [ssh_keyfile], :paranoid => Net::SSH::Verifiers::Null.new) do |ssh|
      result = ssh.exec!("sudo -u oracle -- sh -c 'chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::update-wls-cert]' --json-attributes /tmp/renew_asset.json -l info'")
      #result = ssh.exec!("sudo -u oracle -- sh -c 'echo 'whoami';whoami")
      puts "#{result}"
      if result.scan(Regexp.union(errmsg)).size > 0
        raise "Fatal error while updating WLS Cert in #{host}"
      end
    end
    Chef::Log.info("Successfully executed update-wls-cert recipe on target node #{host} ..")
  rescue Exception
    Chef::Log.error("Fatal error while updating WLS Cert in #{host}")
    raise
  end
end

def updateOTDConfigCert(host,errmsg)
  begin
    Chef::Log.info("Updating OTD Config Cert in #{host} ..")
    ssh_keyfile="/home/mintpress/mintpress/.ssh/id_rsa"
    Chef::Log.info("Starting Executing update-otd-config-cert recipe on target node #{host} ..")
    Net::SSH.start(host, "mintpress", :keys => [ssh_keyfile], :paranoid => Net::SSH::Verifiers::Null.new) do |ssh|
      result=ssh.exec!("sudo -u oracle -- sh -c 'chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::update-otd-config-cert]' -l info'")
      puts "#{result}"
      if result.scan(Regexp.union(errmsg)).size > 0
        raise "Fatal error while updating WLS Cert in #{host}"
      end
    end
    Chef::Log.info("Successfully executed update-otd-config-cert recipe on target node #{host} ..")
  rescue Exception
    Chef::Log.error("Fatal error while Updating OTD Config Cert in #{host}")
    raise
  end
end

def rsyncCerts(tenant,env_name,asset,archive_dir_name)
  asset_identifier = asset.gsub("obp-","").gsub("obp","")
  ready_dir = "/environmint/certificates/certs_ready/#{tenant}/#{env_name}"

# Actual Directories
#  live_dir = "/stage/extracted/certs/#{tenant}/#{env_name}"
#  archive_dir = "/environmint/certificates/certs_archive/#{tenant}/#{env_name}"

# Below are test directories
  live_dir = "/stage/extracted/certs/test_sync/#{tenant}/#{env_name}"
  archive_dir = "/environmint/certificates/test_sync/certs_archive/#{tenant}/#{env_name}"

  #Check if Source certs exists
  if  Dir.glob("#{ready_dir}/*#{asset_identifier}*").empty?
    puts "No files to Sync from Source Certs Folder - #{ready_dir} " 
  else
    #Archive And Copy Certs to Stage Folder
    FileUtils.cd("#{ready_dir}")
    Dir.glob("*#{asset_identifier}*").each do |f|
      puts "Inspecting Cert file - #{f}"
      if File.exists?("#{live_dir}/#{f}")
        next puts "Existing and New Cert Files are same - #{live_dir}/#{f} and #{ready_dir}/#{f} " if FileUtils.cmp("#{live_dir}/#{f}","#{ready_dir}/#{f}")
        puts "Moving #{f} to Archive Folder #{archive_dir}/#{archive_dir_name}"
        FileUtils.mkdir_p("#{archive_dir}/#{archive_dir_name}")
        FileUtils.mv("#{live_dir}/#{f}", "#{archive_dir}/#{archive_dir_name}")
        puts "Archived Cert - #{f} successfully "
      else
        puts "No File to Archive, proceeding to Copy"
      end
      puts "Copying #{f} to Live Folder"
      FileUtils.mkdir_p("#{live_dir}")
      FileUtils.cp "#{ready_dir}/#{f}", "#{live_dir}/#{f}"
      puts "Copied Cert - #{f} to Live Folder - #{live_dir} Succcessfully"
    end
  end
  
  #Sync CA certs
  ca_cert_list = ["adapters.jks", "cacerts", "cacerts.pem"]
  ca_cert_list.each do |ca|
   FileUtils.cp "/oracle/stage/certs/#{ca}", "#{live_dir}/" unless File.exists?("#{live_dir}/#{ca}") && FileUtils.cmp("/oracle/stage/certs/#{ca}","#{live_dir}/#{ca}")
  end
  
  #Copy WBCTrust.jks only if it doesn't exist
  FileUtils.cp "#{ready_dir}/WBCTrust.jks", "#{live_dir}/" unless File.exists?("#{live_dir}/WBCTrust.jks")

  #Update File permissions so that oracle user can read
  FileUtils.chmod_R 0755, "#{live_dir}"
  
  # Rsync Certs to EXA Stage
  if "#{env_name}" =~ /^prd\d*/
    exa_rcc_stage = "ehprprd1bkp01.rad.wbcau.westpac.com.au"
    exa_wsdc_stage = "ehpwprd1bkp01.rad.wbcau.westpac.com.au"
    ssh_keyfile = "gemini_prod_mintpress_key"
  else
    exa_rcc_stage = "ehprtst1bkp01.radtest.wbctestau.westpac.com.au"
    exa_wsdc_stage = "ehpwtst1bkp01.radtest.wbctestau.westpac.com.au"
    ssh_keyfile = "gemini_nonprod_mintpress_key"
  end
  puts "Executing Rsync Of New Certs To EXA Stage"
  ["#{exa_rcc_stage}","#{exa_wsdc_stage}"].each do |server|
    puts "Rsyncing to server - #{server}"
    rsync_out=%x[rsync -av -e "ssh -i ~/.ssh/#{ssh_keyfile}" #{live_dir}/ #{server}:/oracle/stage/certs/test_sync/#{tenant}/#{env_name}/]
    puts rsync_out
  end
end

if action=='update-certs'
  cert_asset_list.each do |asset|
    rsyncCerts(tenant,environment_name,asset,archive_dir_name)
    #Chef::Log.info("Starting Cert Update for asset - #{asset}")
    #if asset == 'obpotd'
    #  otd_host=my_topology_vars["#{asset}"]['hostnameList'][0]+my_topology_vars["#{asset}"]['dns_domain_name']
    #  otd_host2=my_topology_vars["#{asset}"]['hostnameList'][1]+my_topology_vars["#{asset}"]['dns_domain_name']
    #  Chef::Log.info("Updating certs of otd configurations for  - #{otd_host}")
    #  updateOTDConfigCert(otd_host,errmsg)
    #  updateWLSCert(otd_host,errmsg)
    #  updateWLSCert(otd_host2,errmsg)
    #else      
    #  my_topology_vars["#{asset}"]['hostnameList'].each_with_index do |host|
    #    Chef::Log.info("Updating certs  for host - #{host}")
    #    host_fqdn = host+my_topology_vars["#{asset}"]['dns_domain_name']
    #    updateWLSCert(host_fqdn,errmsg)
    #  end
    #end
  end
elsif action=='renew-certs'
  bash 'Executing recipe - renew_existing from cookbook - wbc-cert-mgmt' do
    code <<-EOH
    chef-client --lockfile /tmp/cheflock$$ -E #{environment_name} --config ~/.chef/client-#{tenant}.rb --config-option file_cache_path=/environmint/caches/#{tenant}/.chef/#{environment_name}-cache -o obp-environmint-custom,wbc-cert-mgmt::renew_existing -j /tmp/#{tenant}-#{environment_name}-cert-build.json -l info
    EOH
  end
elsif action=='request_new-certs'
  bash 'Executing recipe - request_new from cookbook - wbc-cert-mgmt' do
    code <<-EOH
    chef-client --lockfile /tmp/cheflock$$ -E #{environment_name} --config ~/.chef/client-#{tenant}.rb --config-option file_cache_path=/environmint/caches/#{tenant}/.chef/#{environment_name}-cache -o obp-environmint-custom,wbc-cert-mgmt::request_new -j /tmp/#{tenant}-#{environment_name}-cert-build.json -l info
    EOH
  end
end