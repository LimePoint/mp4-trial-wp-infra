# Disable the profile on limits for all dbs.
# this is not a good practice, however, these are DEV systems and we shouldn't care if a password is wrong

nonDefault_Params_Static = {"_allow_insert_with_update_check" => "true"}
nonDefault_Params_Dynamic = {}

node['oracle']['database']['databaseList'].each do |database|

    nonDefault_Params_Static.each do |sp,v|
        oracle_sql "setting parameter #{sp} for #{database['name']}" do
            oracle_home database['oracle_home']
            db_service_name database['name']
            db_host 'localhost'
            db_port node['oracle']['database']['listenerList'][0]['port']
            db_username database['sysdba_user']
            db_password database['sysdba_passwd']
            as_sysdba true
            sql "ALTER SYSTEM SET \"#{sp}\" = #{v} COMMENT = 'Updated by ENVIRONMINT(R)' SCOPE = SPFILE SID = '*'"
            sql_verify "SELECT COUNT(1) FROM V$SYSTEM_PARAMETER WHERE LOWER(NAME) = '#{sp.downcase}' AND LOWER(TO_CHAR(VALUE)) = TO_CHAR('#{v.downcase}')"
            user 'oracle'
            group 'oinstall'
            action :run
            notifies :shutdown, "oracle_service[Shutdown #{database['name']}]"
        end
    end

    nonDefault_Params_Dynamic.each do |dp,v|
        oracle_sql "setting parameter #{dp} for #{database['name']}" do
            oracle_home database['oracle_home']
            db_service_name database['name']
            db_host 'localhost'
            db_port node['oracle']['database']['listenerList'][0]['port']
            db_username database['sysdba_user']
            db_password database['sysdba_passwd']
            as_sysdba true
            sql "ALTER SYSTEM SET \"#{dp}\" = #{v} COMMENT = 'Updated by ENVIRONMINT(R)' SCOPE = BOTH SID = '*'"
            sql_verify "SELECT COUNT(1) FROM V$SYSTEM_PARAMETER WHERE LOWER(NAME) = '#{dp.downcase}' AND LOWER(TO_CHAR(VALUE)) = TO_CHAR('#{v.downcase}')"
            user 'oracle'
            group 'oinstall'
            action :run
        end
    end

    oracle_service "Shutdown #{database['name']}" do
        oracle_home database['oracle_home']
        database_name database['name'].gsub('_','')
        options "IMMEDIATE"
        user 'oracle'
        group 'oinstall'
        action :nothing
        notifies :startup ,"oracle_service[Startup #{database['name']}]", :immediate
    end

    oracle_service "Startup #{database['name']}" do
        oracle_home database['oracle_home']
        database_name database['name'].gsub('_','')
        user 'oracle'
        group 'oinstall'
        action :startup
    end

end
