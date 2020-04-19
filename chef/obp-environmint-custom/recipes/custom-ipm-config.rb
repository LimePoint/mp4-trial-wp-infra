# This recipe sets custom config params for OBPIPM asset


Chef::Log.info('Set custom params for IPM/content server')

require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

environment_name = node.chef_environment.downcase
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

asset_vars = my_topology_vars['obpipm']
intradoc_port = my_topology_vars['obpipm']['ucm_server']['intradoc_port']
node_sn = node.name.split('.')[0].downcase

# Update config.cfg from Node Only
if node_sn == my_topology_vars['obpipm']['hostnameList'][0]
  config_file  = "/oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/config/config.cfg"

  ruby_block "Modify config.cfg file #{config_file}" do
    block do

      file = Chef::Util::FileEdit.new(config_file)
      file.insert_line_if_no_match(/AllowMatchesInDateCheck/, "AllowMatchesInDateCheck=true")
      file.insert_line_if_no_match(/DisableSharedCacheChecking/, "DisableSharedCacheChecking=true")
      file.insert_line_if_no_match(/ArchiverDoLocks/, "ArchiverDoLocks=true")
      file.search_file_replace_line(/IntradocServerPort=4444/, "IntradocServerPort=#{my_topology_vars['obpipm']['ucm_server']['intradoc_port']}")
      file.write_file
    end
    only_if { ::File.exists?(config_file) }
  end

  setDomainEnv_file  = "/oracle/app/runtime/obpipm/domains/obpipm_domain/bin/setDomainEnv.sh"

  ruby_block "Modify setDomainEnv.sh file #{setDomainEnv_file}" do
    block do

      file = Chef::Util::FileEdit.new(setDomainEnv_file)
      file.insert_line_if_no_match(/GDFONTPATH/, "export GDFONTPATH=/usr/share/fonts/msttfonts/")
      file.write_file
    end
    only_if { ::File.exists?(setDomainEnv_file) }
  end
end

# Run On All Nodes

intradoc_file  = "/oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/ucm/cs/bin/intradoc.cfg"

ruby_block "Modify intradoc.cfg file #{intradoc_file}" do
  block do

    file = Chef::Util::FileEdit.new(intradoc_file)
    file.insert_line_if_no_match(/VaultTempDir/, "VaultTempDir=/oracle/app/runtime/obpipm/#{environment_name}/ucm/cs/vault/~temp/")
    file.insert_line_if_no_match(/TraceDirectory/, "TraceDirectory=/oracle/app/logs/obpipm/obpipm_domain/trace/")
    file.insert_line_if_no_match(/EventDirectory/, "EventDirectory=/oracle/app/logs/obpipm/obpipm_domain/event/")
    file.write_file
  end
  only_if { ::File.exists?(intradoc_file) }
end

setDomainEnv_file  = "/oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/bin/setDomainEnv.sh"

ruby_block "Modify setDomainEnv.sh file #{setDomainEnv_file}" do
  block do

    file = Chef::Util::FileEdit.new(setDomainEnv_file)
    file.insert_line_if_no_match(/GDFONTPATH/, "export GDFONTPATH=/usr/share/fonts/msttfonts/")
    file.write_file
  end
  only_if { ::File.exists?(setDomainEnv_file) }
end