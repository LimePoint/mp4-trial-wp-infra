# Disable the profile on limits for all dbs.
# this is not a good practice, however, these are DEV systems and we shouldn't care if a password is wrong

template 'Script to Check and SET Tablespace MAXSIZE to Unlimited' do
    source "sql/check-ts-usage.sql.erb"
    path "/tmp/.check-ts-usage.sql"
    variables (
        variables( :env => node.chef_environment)
    )
    mode '0600'
    user 'oracle'
    group 'oinstall'
end

node['oracle']['database']['databaseList'].each do |database|

    dbSID = database['version'] == "12.2.0.1" ? database['name'].gsub('_','') : database['name'].gsub('_','')[0..7]

    bash "Check Tablespace usage on #{database['name']}" do
        code <<-EOH
        export ORACLE_HOME="#{database['oracle_home']}"
        export LD_LIBRARY_PATH="#{database['oracle_home']}/lib"
        export PATH="$ORACLE_HOME/bin:$PATH"
        export ORACLE_SID="#{dbSID}"
        echo "TABLESPACE USAGE in ${ORACLE_SID}"
        echo "==================================="
        sqlplus /nolog <<EOSQL
        connect / as sysdba
        @/tmp/.check-ts-usage.sql
        exit;
        EOH
    end
end
