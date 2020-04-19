# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

asset_list = ['obpobh','obpobu','obpsoa','obposb','obpbip','obpodi','obpcid','obpcim','obpoam','obpoid','obpoim','obpipm','obpdoc','obpurm']
_item_code = 'OBPDATAEXTRACT'
environment_name = node.chef_environment.downcase

asset_code = node['asset_code']
schema_list = node['schema_list']
target_db = node['target_db']
return unless asset_list.include?(asset_code)

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
db_version = my_topology_vars['common'].key?('database_version') ? my_topology_vars['common']['database_version'] : "12.1.0.2"
folder="/tmp/tmp_dpump"
parfile="#{folder}/expdp.par"
dumpfile=Time.now.strftime("expdp_#{environment_name.upcase}_#{asset_code}_%Y%m%d_%H%M")+"_%U.dmp"

node['oracle']['database']['databaseList'].each do |database|
    if db_version == "12.1.0.2"
        db_svc_name = database['name'].gsub('_', '')[0..7]
    else
        db_svc_name = database['name'].gsub('_', '')
    end
    if database['name'].include?(target_db)
        directory "#{folder}" do
           recursive true
           action :delete
           ignore_failure true
        end
        directory "#{folder}" do
           owner 'oracle'
           group 'oinstall'
           mode '0750'
           action :create
        end
        file "#{parfile}" do
            owner 'oracle'
            group 'oinstall'
            mode '0644'
            content "PARALLEL=4\nCOMPRESSION=ALL\nCOMPRESSION_ALGORITHM=medium\nSCHEMAS=#{schema_list}\nflashback_time=\"TO_TIMESTAMP(to_char(sysdate,'YYYYMMDDHH24MISS'),'YYYYMMDDHH24MISS')\""
        end

        oracle_sql "Creating DB directory for #{folder}" do
            sql "CREATE OR REPLACE directory DATA_STAGE as '#{folder}'"
            db_service_name db_svc_name
            db_host 'localhost'
            db_port 1521
            db_username database['sysdba_user']
            db_password database['sysdba_passwd']
            oracle_home database['oracle_home']
            as_sysdba true
            user 'oracle'
            group 'oinstall'
        end

        log "Running datapump export, dumping files to #{folder}"
        oracle_datapump "Extracting schemas #{schema_list} for #{asset_code}" do
            file dumpfile
            directory_path folder
            options "parfile=#{parfile}"
            logfile "DATA_PUMP_DIR:expdp_#{environment_name.upcase}_#{asset_code}_mintpress.log"
            oracle_home database['oracle_home']
        # FIXME: this is working around an MP bug
            db_service_name db_svc_name
            db_host 'localhost'
            db_port 1521
            db_username database['sysdba_user']
            db_password database['sysdba_passwd']
            as_sysdba true
            user 'oracle'
            group 'oinstall'
            action :export
            notifies :run, "oracle_sql[Drop DATA_STAGE]"
        end
        log "Datapump Export Successful."
        oracle_sql "Drop DATA_STAGE" do
            sql "DROP directory DATA_STAGE"
            db_service_name db_svc_name
            db_host 'localhost'
            db_port 1521
            db_username database['sysdba_user']
            db_password database['sysdba_passwd']
            oracle_home database['oracle_home']
            as_sysdba true
            user 'oracle'
            group 'oinstall'
            action :nothing
            ignore_failure true
        end
    end
end
