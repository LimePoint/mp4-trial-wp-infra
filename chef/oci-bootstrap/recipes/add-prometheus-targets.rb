hostlist=[]

# Find all environments we have
search(:environment).each do |env|
    hostlist = []
    # Reset hostlist
	begin
      search(:node, "chef_environment:#{env}").each do |host|
          begin
              hostlist << "#{host['hostname']}:9100"
          rescue
		    Chef::Log.info ("No hosts found for environment [#{env}]")
          end
      end
      hostlist = hostlist.sort.uniq
      
      # Add a file per environment
      template "/oracle/prometheus/prometheus-2.17.2.linux-amd64/envs/#{env}.yaml" do
        source 'prometheus-hosts.yaml.erb'
        variables(host_list: hostlist, environment_name: env)
      end
	rescue
		Chef::Log.info ("No environments found for Prometheus. No Action")
	end
end

