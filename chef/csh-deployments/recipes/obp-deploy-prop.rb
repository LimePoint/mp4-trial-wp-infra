Chef::Log.info("Generate Deploy Prop files")

environment_name = node.chef_environment.downcase
#environment_name = node['environment']

env_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')
puts "Env Code "
puts env_code

Chef::Log.info("Fetching Data Bags for  #{environment_name} using the manifest file environment name ")

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{environment_name}_vars.json"))
vars = my_topology_vars.clone
vars.merge!(Hash({'environment_name' => env_code}))

my_dep_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_dep_vars.json"))
vars = vars.merge(my_dep_vars)


puts "Finding the CSH Release Version "
csh_release_version = vars['deployment']['CSH_RELEASE_VERSION']
puts "This environments is tagged for  CSH Release: #{csh_release_version} "
if csh_release_version.nil?
    deployment_prop_template_source  = "deployment"
else
    deployment_prop_template_source  = "#{csh_release_version}/deployment-props"
end
puts "This Orchestration will use template from this folder : #{deployment_prop_template_source}"

final_folder="/oracle/app/binaries/deployments/mintdeploy/deploymentProperties/#{environment_name}"
unless File.directory?(final_folder)
  FileUtils.mkdir_p(final_folder)
end
::Dir.glob("#{__dir__}/../templates/#{deployment_prop_template_source}/*.erb").each do |f|
bn=::File.basename(f)
template "#{final_folder}/#{bn.gsub('.erb','')}" do
  source "#{deployment_prop_template_source}/#{bn}"
  variables vars
  end.run_action(:create)
end
Chef::Log.info("Completed execution of the Custom Build json file")

