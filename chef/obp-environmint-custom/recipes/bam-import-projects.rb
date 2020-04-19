# Author: Romil Bhagat

# This file loads the base OBP schema into OID and should be used during the configure online phase of OID build
# This can be run over and over again and it was just ignore the entries.

node.run_state.merge!(node)

environment_code = node.chef_environment
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_code}_vars.json"))
password_vault_name = my_topology_vars['common']['password_vault_name']
release_version = my_topology_vars['obpsoa']['release_version']

log "Importing BAM projects"

if release_version == '2.6.1'
	bash 'Import BAM Projects' do
	  code <<-EOH
	    export JAVA_HOME="/oracle/app/binaries/obpsoa/java"
	    cd /oracle/app/binaries/obpsoa/fmw/soa/bam/bin 
	    /oracle/app/binaries/obpsoa/fmw/soa/bam/bin/bamcommand -cmd import -file /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/workflow/bam/projects/OperationsManagerProject.zip -mode update -type project -contents 0
	    /oracle/app/binaries/obpsoa/fmw/soa/bam/bin/bamcommand -cmd import -file /oracle/app/binaries/obpsoa/fmw/obpinstall/obp/workflow/bam/projects/UserProject.zip -mode update -type project -contents 0
	    EOH
	end

	log "Imported BAM projects successfully"
elsif release_version == '2.6.2'
	bash 'Copy BAM Artefacts ' do
	  code <<-EOH
	    unzip -o /oracle/stage/obp/2.6.2/obp-soa/obpinstall-soa/bam.zip -d /oracle/app/binaries/obpsoa/fmw/obpinstall/ob.bam
	    cd /oracle/app/binaries/obpsoa/fmw/obpinstall/ob.bam
	    /oracle/app/binaries/obpsoa/fmw/soa/bam/bin/bamcommand -cmd import -file /oracle/app/binaries/obpsoa/fmw/obpinstall/ob.bam/projects/OperationsManager.zip -mode update -type project -contents 0
	    /oracle/app/binaries/obpsoa/fmw/soa/bam/bin/bamcommand -cmd import -file /oracle/app/binaries/obpsoa/fmw/obpinstall/ob.bam/projects/User.zip -mode update -type project -contents 0
	    /oracle/app/binaries/obpsoa/fmw/soa/bam/bin/bamcommand -cmd import -file /oracle/app/binaries/obpsoa/fmw/obpinstall/ob.bam/projects/Application.zip -mode update -type project -contents 0
	    EOH
	end
else
	log "OBP release version - #{release_version} is not supported. Please check the release_version in the env_vars"
	return
end
	
