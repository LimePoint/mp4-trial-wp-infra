Chef::Log.info("Generate node Prop files")

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
File.open("/tmp/node.json","w") {|f| f.write(JSON.pretty_generate(vars))}
Chef::Log.info("Completed execution of the Custom node generated json")