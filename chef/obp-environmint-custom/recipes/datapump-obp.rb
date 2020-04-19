# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code = 'OBPOBH'

environment_name = node.chef_environment.downcase
environment_code = environment_name.strip.tr('.', '').tr('_', '').tr('-', '').tr(' ', '')

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

# Drop the OBP Schema
log "---------- Dropping OBPHOST Schema"
include_recipe '::drop-obphostschema'
log "---------- Dropping OBPHOST Schema Successful"

# Create the OBP Schema
log "---------- Creating OBPHOST Schema"
include_recipe '::create-obphostschema'
log "---------- OBPHOST Schema Created Successful"

node['oracle']['database']['databaseList'].each do |database|

	# Add more storage so that data pump does not dies
	if database['name'].include?('OBP_PRIM')
		log "Adding more storage to the OBPHOST tablespace if required."
		3.times do |c|
			oracle_sql "ensure file #{c}" do
				sql "alter tablespace OBPHOST_obp add datafile '/oracle/app/oradata/CBCD3OBPPRIM/OBPHOST_obp_#{c}.dbf' size 1G autoextend on maxsize 30G"
				sql_verify "select count(*) from v$datafile where name='/oracle/app/oradata/CBCD3OBPPRIM/OBPHOST_obp_#{c}.dbf'"
				# FIXME: this is working around an MP bug
				db_service_name database['name'].gsub('_', '')[0..7]
				db_host 'localhost'
				db_port 1521
				db_username database['sysdba_user']
				db_password database['sysdba_passwd']
				oracle_home database['oracle_home']
				as_sysdba true
				user 'oracle'
				group 'oinstall'
			end
		end

		# Now load the data dump
		# TODO RB: this logic has to change to be more suitable; this involves manual work for now
		# The standard is going to be $STAGE/$SOURCE_ENVIRONMENT/$DATE, e.g /oracle/stage/db_dumps/dev3/2018-07-11
		folder="#{my_topology_vars['common']['dataload_path']}/"
		log "Running data pump, picking files from #{folder}"
		oracle_datapump "Import into OBP Database" do
			file ::Dir.glob(folder+'*.dmp').map { |s| s.gsub(folder, '') }.sort()
			directory_path folder
			options 'PARALLEL=3'
			logfile "DATA_PUMP_DIR:#{node.chef_environment.upcase}_datapump_mintpress.log"
			# FIXME: WRONG WRONG WRONG WRONG WRONG
			# RB: Dont enable this - this will not work if the import failed for some reason;
			# RB: We assume that if the user has requested data load, they are certain that it needs to happen
			sql_verify "SELECT count(1) from DBA_TABLES WHERE TABLE_NAME='THIS_NON_EXISTENT_TABLE' AND OWNER='OBPHOST_OBP'"
			oracle_home database['oracle_home']
			# FIXME: this is working around an MP bug
			db_service_name database['name'].gsub('_', '')[0..7]
			db_host 'localhost'
			db_port 1521
			db_username database['sysdba_user']
			db_password database['sysdba_passwd']
			as_sysdba true
			user 'oracle'
			group 'oinstall'
			action :import
			ignore_failure true
		end
		log "Data pump Successful."

		# UTL RP - recompile invalid objects
		log "Recompiling OBPHOST Schema..."
		oracle_sql "Recompile Schema" do
			sql "EXEC UTL_RECOMP.recomp_serial('OBPHOST_OBP')"
			# sql "exec dbms_utility.compile_schema('OBPHOST_OBP')"
			#sql_verify "select count(*) from v$tablespace where name='/oracle/app/oradata/CBCD3OBPPRIM/OBPHOST_obp_#{c}.dbf'"
			# FIXME: this is working around an MP bug
			db_service_name database['name'].gsub('_', '')[0..7]
			db_host 'localhost'
			db_port 1521
			oracle_home database['oracle_home']
			db_username database['sysdba_user']
			db_password database['sysdba_passwd']
			as_sysdba true
			user 'oracle'
			group 'oinstall'
		end
		log "OBPHOST Schema Recompile Successful."

		# Reset the CZ tables for OBP to make sure that the db incrementals work properly
		# src_env_list=''
		# ['trg', 'dev', 'tst', 'cix'].each do |etype|
		# 	10.times do |enum|
		# 		src_env="#{etype}#{enum}"
		# 		src_env_list = src_env_list + "'" + src_env + "',"
		# 	end
		# end
		# src_env_list = src_env_list.chomp(",").upcase
		sql_to_run = "Update OBPHOST_OBP.CZ_AF_DB_DEPLOY_LOG SET ENVNAME='#{node.chef_environment.upcase}'"
		
		log "Updating CZ tables with query --- #{sql_to_run}"
		oracle_sql "Update CZ_AF_DB_DEPLOY_LOG" do
			# sql "update OBPHOST_OBP.CZ_AF_DB_DEPLOY_LOG SET ENVNAME='#{node.chef_environment.upcase}' where upper(ENVNAME) in (#{src_env_list})"
			sql sql_to_run
			# FIXME: this is working around an MP bug
			db_service_name database['name'].gsub('_', '')[0..7]
			db_host 'localhost'
			db_port 1521
			oracle_home database['oracle_home']
			db_username database['sysdba_user']
			db_password database['sysdba_passwd']
			as_sysdba true
			user 'oracle'
			group 'oinstall'
		end
		log "OBPHOST_OBP.CZ_AF_DB_DEPLOY_LOG Updated Successfully."

	end

end
