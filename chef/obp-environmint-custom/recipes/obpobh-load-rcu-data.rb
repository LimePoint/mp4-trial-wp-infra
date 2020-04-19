require 'tempfile'
require 'base64'


# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

if is_running_on_cloud

	environment_name = node.chef_environment.downcase
	asset_code = 'obpobh'

	my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))

    if my_topology_vars['common']['remap_schema'].nil?
		remap_schema = ''
    else
		remap_schema = my_topology_vars['common']['remap_schema']
    end

    if my_topology_vars['common']['remap_tablespace'].nil?
		remap_tablespace = ''
	else
		remap_tablespace = my_topology_vars['common']['remap_tablespace']
	end

    if my_topology_vars['common']['database_version'] == '12.2.0.1'
		dbSID = my_topology_vars["#{asset_code}"]['database']['service_name'].gsub('_', '')
	else
		dbSID = my_topology_vars["#{asset_code}"]['database']['service_name'].gsub('_', '')[0..7]
	end

    oratabLoc = '/etc/oratab'
    if File.exists?(oratabLoc)
        findOH="grep #{dbSID} #{oratabLoc}|awk -F: '{print $2}'"
    else
        findOH="find /oracle/app -name 'oraInst.loc' -type f -exec dirname {} \\\;|grep '\\\/db'"
    end
    orcl_home = %x[#{findOH}].chomp

    if node['dpdump_loc'].nil?
        dataload_path = my_topology_vars['common']['dataload_path'].chomp("/") + "/"
    else
        dataload_path = node['dpdump_loc'].chomp("/") + "/"
    end

    if node['forcekill'].nil?
        forcekill = 'FALSE'
    else
        forcekill = node['forcekill'].upcase
    end

	pwd_vault = my_topology_vars['common']['password_vault_name']
	rcu_prefix = my_topology_vars["#{asset_code}"]['database']['rcu_schema_prefix']
	schema_name = "#{rcu_prefix}_OBP"
	schema_pwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{asset_code}/#{rcu_prefix}").value)
	sysdba_user = my_topology_vars["#{asset_code}"]['database']['sysdba_username']
	syspwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{asset_code}/#{sysdba_user}").value)

	readonly_username = 'obpreadonly'
	readonly_password = Mint::AesEncryption.decrypt(PasswordVault.get_password(pwd_vault, asset_code, 'obpreadonly'))
	datapump_directory_name = 'OBP_DATA_PUMP'
	database_host = my_topology_vars[asset_code]['database']['scan_address']
	database_port = my_topology_vars[asset_code]['database']['listen_port'].to_i
    if my_topology_vars[asset_code]['release_version'].nil?
        rel_ver = "2.6.2"
    else
        rel_ver = my_topology_vars[asset_code]['release_version']
    end

	tns_entry = "OBP_DATAPUMP=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=#{database_host})(PORT=#{database_port}))(CONNECT_DATA=(SERVICE_NAME=#{dbSID})))"
	datapump_files = ::Dir.glob(dataload_path + '*.dmp').map { |s| s.gsub(dataload_path, '') }.sort().join(',')
    raise "Found no dumpfiles in '#{dataload_path}'. Please provide a VALID path and TRY AGAIN!!" if datapump_files == ""

    template "Preparing to re-ceate #{schema_name} schema" do
		source "sql/recreate-obphost-schema.sql.erb"
		path "/tmp/.recreate-obphost-schema.sql"
		variables(
            :asset_code => asset_code,
            :release_version => rel_ver,
            :username => schema_name,
			:userpassword => schema_pwd,
			:readonly_username => readonly_username,
			:readonly_userpassword => readonly_password,
			:datapump_dirname => datapump_directory_name,
			:datapump_dir => dataload_path.chomp("/"),
            :forcekill => forcekill
		)
		mode '0600'
		user 'oracle'
		group 'oinstall'
	end

    template "Privileges for #{schema_name} schema" do
		source "sql/#{asset_code}-dbprivs-#{rel_ver}.sql.erb"
		path "/tmp/#{asset_code}-dbprivs-#{rel_ver}.sql"
		variables(
            :username => schema_name
		)
		mode '0600'
		user 'oracle'
		group 'oinstall'
	end

    bash "Re-Creating #{schema_name} schema" do
        code <<-EOH
        export ORACLE_HOME="#{orcl_home}"
        export LD_LIBRARY_PATH="#{orcl_home}/lib"
        export PATH="$ORACLE_HOME/bin:$PATH"
        sqlplus /nolog <<EOSQL
        connect #{sysdba_user}/#{syspwd}@#{tns_entry.gsub('OBP_DATAPUMP=','')} as sysdba
        @/tmp/.recreate-obphost-schema.sql
        exit;
        EOSQL
        EOH
    end

	log "Adding more storage to the OBPHOST tablespace if required."
	3.times do |c|
		oracle_sql "ensure file #{c}" do
			sql "alter tablespace OBPHOST_obp add datafile '/oracle/app/oradata/CBCD3OBPPRIM/OBPHOST_obp_#{c}.dbf' size 1G autoextend on maxsize 30G"
			sql_verify "select count(*) from v$datafile where name='/oracle/app/oradata/CBCD3OBPPRIM/OBPHOST_obp_#{c}.dbf'"
			oracle_home orcl_home
			db_service_name dbSID
			db_host database_host
			db_port database_port
			db_username sysdba_user
			db_password syspwd
			as_sysdba true
			user 'oracle'
			group 'oinstall'
		end
	end

	log "Running data pump, picking files from #{dataload_path}"
	template 'Data Import Prepare' do
		source "ocloud-remote-import.sh.erb"
		path "/tmp/.ocloud-remote-import.sh"
		variables(
			:database_home => orcl_home,
			:tns_entry => tns_entry,
			:database_sys_username => sysdba_user,
			:database_sys_userpassword => syspwd,
			:datapump_directory_name => datapump_directory_name,
			:datapump_files => datapump_files,
            :environment_name => environment_name,
            :remap_schema => remap_schema,
            :target_schema => schema_name,
            :remap_tablespace => remap_tablespace,
            :target_tablespace => 'OBPHOST_OBP'
		)
		mode '0600'
		user 'oracle'
		group 'oinstall'
	end

	bash 'Data Import Run' do
		code <<-EOH
	sh /tmp/.ocloud-remote-import.sh
	rm -f /tmp/.ocloud-remote-import.sh
	rm -f /tmp/.recreate-obphost-schema.sql
		EOH
		user 'oracle'
		group 'oinstall'
		ignore_failure true
        timeout 7200
	end

	log 'Data pump Successful.'

	log 'Recompiling OBPHOST Schema...'
	oracle_sql 'Recompile Schema' do
		sql "EXEC UTL_RECOMP.recomp_serial('OBPHOST_OBP')"
		oracle_home orcl_home
		db_service_name dbSID
		db_host database_host
		db_port database_port
		db_username sysdba_user
		db_password syspwd
		as_sysdba true
		user 'oracle'
		group 'oinstall'
	end
	log 'OBPHOST Schema Recompile Successful.'

	sql_to_run = "Update OBPHOST_OBP.CZ_AF_DB_DEPLOY_LOG SET ENVNAME='#{node.chef_environment.upcase}'"

	log "Updating CZ tables with query --- #{sql_to_run}"
	oracle_sql 'Update CZ_AF_DB_DEPLOY_LOG' do
		sql sql_to_run
		oracle_home orcl_home
		db_service_name dbSID
		db_host database_host
		db_port database_port
		db_username sysdba_user
		db_password syspwd
		as_sysdba true
		user 'oracle'
		group 'oinstall'
	end
	log 'OBPHOST_OBP.CZ_AF_DB_DEPLOY_LOG Updated Successfully.'

end
