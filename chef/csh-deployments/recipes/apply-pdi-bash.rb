# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)


env_name = node.chef_environment.downcase

_item_code = 'obpobh'

my_topology_vars = JSON.parse(::File.read("#{__dir__}/../../obp-environmint-custom/files/data_bags/#{env_name}_vars.json"))

asset_vars = my_topology_vars[_item_code.downcase]

pwd_vault = my_topology_vars['common']['password_vault_name']
pdi_home='/oracle/app/binaries/deployments/pdi'
rcu_prefix = my_topology_vars["#{_item_code}"]['database']['rcu_schema_prefix']
schema_name = "#{rcu_prefix}_OBP"
schema_pwd = Mint::AesEncryption.decrypt(PasswordVault.secret("databag://#{pwd_vault}/#{_item_code}/#{rcu_prefix}").value)

bash "Execute the SQL scripts to deploy Prod DB Incr" do
    cwd pdi_home
    code <<-EOSH
    export TNS_ADMIN=/home/oracle
    export ORACLE_HOME=/oracle/app/binaries/obpobh/dbclient
    export LD_LIBRARY_PATH=$ORACLE_HOME/lib
    export PATH=$PATH:$ORACLE_HOME/bin

    function sql_exec {
        echo -e "\n Executing script '${1}' in '${PWD}'"
        sqlplus -s #{schema_name}/#{schema_pwd}@hostdb <<EOSQL
        set trims on timi on echo on
        @@${1}
        set head off
        select ' Executed "${1}" ' from dual;
        host mv ${1} ${1}_executed
        exit;
EOSQL
    }

    for i in `ls -d *[0-9]`; do
        cd ${i} && echo -e "\n Changed directory to:${PWD}";
        if [ -d "SCRIPTS" ]; then
            if [ -d "SCRIPTS/OBJ_MODIFICATION" ]; then
                cd "SCRIPTS"
                test -f "master.sql" && sql_exec "master.sql"
                cd ..
            else
                test -f "SCRIPTS/master.sql" && sql_exec "SCRIPTS/master.sql"
            fi
        fi

        if [ -d "seed" ]; then
            test -f "seed/master.sql" && sql_exec "seed/master.sql"
        fi
        cd ..
    done
    EOSH

end
