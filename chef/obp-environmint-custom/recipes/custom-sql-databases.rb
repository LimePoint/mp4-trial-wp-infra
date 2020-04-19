# Disable the profile on limits for all dbs.
# this is not a good practice, however, these are DEV systems and we shouldn't care if a password is wrong

template 'Script to Check and SET Tablespace MAXSIZE to Unlimited' do
    source "sql/ts-maxsize-check.sql.erb"
    path "/tmp/.ts-maxsize-check.sql"
    mode '0600'
    user 'oracle'
    group 'oinstall'
end

node['oracle']['database']['databaseList'].each do |database|

    dbSID = database['version'] == "12.2.0.1" ? database['name'].gsub('_','') : database['name'].gsub('_','')[0..7]
    oracle_sql 'profile-login-attempts '+database['name'] do
		oracle_home database['oracle_home']
		db_service_name database['name']
		db_host 'localhost'
		db_port 1521
		db_username 'sys'
		db_password database['sysdba_passwd']
		as_sysdba true
		user 'oracle'
		group 'oinstall'
		sql "ALTER PROFILE DEFAULT LIMIT FAILED_LOGIN_ATTEMPTS UNLIMITED"
		action :run
		ignore_failure true
	end

    oracle_sql 'profile-password-lifetime '+database['name'] do
		oracle_home database['oracle_home']
		db_service_name database['name']
		db_host 'localhost'
		db_port 1521
		db_username 'sys'
		db_password database['sysdba_passwd']
		as_sysdba true
		user 'oracle'
		group 'oinstall'
		sql "ALTER PROFILE DEFAULT LIMIT PASSWORD_LIFE_TIME UNLIMITED"
		action :run
		ignore_failure true
	end

    bash "Performing Tablespace Maxsize Check" do
        code <<-EOH
        export ORACLE_HOME="#{database['oracle_home']}"
        export LD_LIBRARY_PATH="#{database['oracle_home']}/lib"
        export PATH="$ORACLE_HOME/bin:$PATH"
        export ORACLE_SID="#{dbSID}"
        sqlplus /nolog <<EOSQL
        connect / as sysdba
        @/tmp/.ts-maxsize-check.sql
        exit;
        EOH
    end
end

#include_recipe "::configure-db-params"
