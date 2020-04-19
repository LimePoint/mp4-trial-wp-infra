
environment_name = node.chef_environment.downcase
env_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')
puts "Env Code "
puts env_code
#    "REPORT_ENABLED": "true"

environment_name = env_code
puts "Chef node dns #{Chef.node['dns']}"
#puts "Chef node dns zone#{Chef.node['dns']['zone']}"

mint_node_name = Chef::Config[:node_name]

puts "Chef node #{mint_node_name}"
if mint_node_name =='ocloud-mintpress.wpdev.mintpress.io'
  puts "We are on Oracle Cloud ...."
  infra = "cloud"
else
  puts "We are not on Oracle  Cloud, should be on prem infrastructure"
  infra = "on-prem"
end


#target_dir = "/home/opc/ml_pod/data-demo/build_reports"
target_dir = node['report']['stage']['remote'][infra]

puts "The Target Directory Remote #{target_dir}"

#final_report_folder="/environmint/tmp/report_files"
final_report_folder=node['report']['stage'][infra]
puts "The Local reporting stage  Directory Remote #{final_report_folder}"

#    rsync -rave "ssh -i ~/.ssh/wpac-ocloud -o StrictHostKeyChecking=no " #{final_report_folder} opc@reports1.wpdev.mintpress.io:#{target_dir}
#manifest_git_repo_path = "/oracle/gitrepos/buildmanifest"
manifest_git_repo_path = node['manifest']['repo'][infra]
puts "The manifest report  #{manifest_git_repo_path}"


remote_host = node['report']['ssh']['remote']['host'][infra]
puts "The remote host    #{remote_host}"


remote_host_key= node['report']['ssh']['remote']['key'][infra]
puts "The remote host key   #{remote_host_key}"


if (remote_host_key.nil? or remote_host.nil? or manifest_git_repo_path.nil? or final_report_folder.nil?)
    puts "The reporting infrastructure is not configured properly, exit now"
    exit(1)

end

ruby_block "fetch response file for cloud" do
  block do
    #Keep this until we read the manifest as raw
    #https://developer.us2.oraclecloud.com/developer03533-a429413/scm/raw/developer03533-a429413_buildmanifest_25999/buildmanifest.git/RB1/manifest.json?revision=master
    Chef::Log.info("TBD provide RO access to every one - read response file directly now")


    %x[ cd #{manifest_git_repo_path} && git log -1 --stat && git pull --quiet ]

    cloud_response_file_path  = "#{manifest_git_repo_path}/RESPONSE_FILES/#{environment_name}_mintpress_response.json"
    Chef::Log.info("Cloud Response File #{cloud_response_file_path}")
    if File.exist?(cloud_response_file_path)
      cloud_response_file= File.read(cloud_response_file_path)
      cloud_response_vars = JSON.parse(cloud_response_file)
      puts cloud_response_vars
      #File.open("/environmint/tmp/response-fetched-#{environment_name.downcase}.json","w") {|f| f.write(cloud_response_vars)}
      puts "Here is response file for cloud [  resource print ] #{cloud_response_vars} "
      node.run_state['response_file']=cloud_response_vars
    else
      Chef::Log.info("No Response File on the cloud , it is a brand new environment")
      resp_vars_init = Hash[ "environment" => "#{environment_name}", "deployments" => {} ]
      node.run_state['response_file']=resp_vars_init
    end
  end
end

ruby_block "flatten  files" do
  block do
    response_vars=node.run_state['response_file']
    consolidated_list =""
    Chef::Log.info("From Compare - response_vars : #{response_vars}")

    response_vars['deployments'].each do | key, data|
      asset_obj = key
      mint_plan = data['mint_plan']
      manifest_ext_version = data['build_version']

      puts asset_obj
      puts  mint_plan
      stat_comp_response = data['statistics']

      if not stat_comp_response.nil?

      end

      if not stat_comp_response.nil?
        puts "there is stat  values for this assets"
        lifeCycleState = stat_comp_response['lifeCycleState']
        buildState = stat_comp_response['buildState']
        buildStartedTime = stat_comp_response['buildStartedTime']
        buildCompletedTime = stat_comp_response['buildCompletedTime']
        buildDurationInSeconds = stat_comp_response['buildDurationInSeconds']
      end
      flattened_hash = Hash[ { "env" => environment_name, "asset" => asset_obj,
                               "enterprise_build_version" => response_vars['enterprise_build_version'],
                               "deploy_start_time" => response_vars['buildStartedTime'] ,
                               "deploy_end_time" => response_vars['deploy_end_time'] ,
                               "e2e_deployment_duration" => response_vars['e2e_deployment_duration'] ,
                               "mint_project_url" => response_vars['mint_project_url'] ,
                               "build_plan" => data['build_plan'], "status" => data['status'] ,
                               "build_version" => data['build_version'] ,
                               "success_version" => data['success_version'],
                               "lifeCycleState" => lifeCycleState ,
                               "buildState" => buildState ,
                               "buildStartedTime" => buildStartedTime,
                               "buildCompletedTime" => buildCompletedTime,
                               "buildDurationInSeconds" => buildDurationInSeconds } ]

      puts flattened_hash
      consolidated_list  << flattened_hash.to_json << "\n"
    end
    puts "Consolidated ======>"
    puts consolidated_list

    unless File.directory?(final_report_folder)
      FileUtils.mkdir_p(final_report_folder)
    end

    project_key = response_vars['mint_project_url']
    project_key = project_key[project_key.rindex("/") +1, project_key.length]
    report_status_file = "#{final_report_folder}/#{environment_name}_#{project_key.downcase}_mint_response.json"
    File.open("#{report_status_file}","w") do | f |
      f.write(consolidated_list)
    end
  end
end

bash "bulldoze files to report server #{target_dir}" do
  code <<-EOH
    cd #{final_report_folder}
    rsync -rave "ssh -i #{remote_host_key} -o StrictHostKeyChecking=no " #{final_report_folder} #{remote_host}:#{target_dir}
  EOH
end