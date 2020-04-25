# Recipe to create databases

password_vault_name = node.chef_environment

# List of databases to create
list_of_dbs = ['CBCD3OSBPRIM', 'CBCD3SECPRIM', 'CBCD3SOAPRIM', 'CBCD3OBPPRIM', 'CBCD3IDMPRIM']
Chef::Log.info "List of Databases to create: #{list_of_dbs}"

# List of services to create against each database
db_to_service_mappings = {
  'CBCD3OSBPRIM' => ['CBCD3_OSB_PRIM','CBCD3_UCM_PRIM'],
  'CBCD3SECPRIM' => ['CBCD3_SEC_PRIM','CBCD3_OBA_PRIM','CBCD3_CST_PRIM'],
  'CBCD3SOAPRIM' => ['CBCD3_SOA_PRIM'],
  'CBCD3OBPPRIM' => ['CBCD3_OBP_PRIM'],
  'CBCD3IDMPRIM' => ['CBCD3_IDM_PRIM','CBCD3_INT_PRIM','CBCD3_DOC_PRIM']
}
Chef::Log.info "List of Database Services to create: #{db_to_service_mappings}"

# First create the databaseList part to be passed on the to node attribute
# databaseList is an array of Hashes
databaseList = []
list_of_dbs.each do | db |
  databaseList << Hash({
  'name' => db,
  'version' => '12.2.0.1',
  'oracle_base' => "/oracle/app/product/db12",
  'oracle_home' => "/oracle/app/product/db12/12.2.0",
  'java_home' => '/oracle/app/product/java12',
  'sysdba_user' => "SYS",
  'sysdba_passwd' => PasswordVault.get_password(password_vault_name, 'database', 'dbsyspassword' ),
  'is_container_db' => false,
  'extra_servicenames' => db_to_service_mappings[db],
  'patchList' => [
      { 'name'  => 'p28662603_122010_Linux-x86-64', 'aru'   => '28662603' },
      { 'name'  => 'p29158680_12201181016DBOCT2018RU_Linux-x86-64', 'aru'   => '29158680' }
  ]
})
end

# Override the environmint-database node attributes
node.normal['oracle']['database'].tap do | database |
  database['datafile_top'] = '/oracle/app/oradata'
  database['archivelog_top'] = '/oracle/app/archive'
  database['flashback_top'] = '/oracle/app/flashback'
  database['databaseList'] = databaseList
  database['listenerList'] = [
    {
      'name' => 'LISTENER',
      'port' => 1521,
      'oracle_home' => '/oracle/app/product/db12/12.2.0'
    }
  ]
end

log "Creating Additional Directories for all databases"
dirs_to_create = '/oracle/app/oradata/CBCD3OBAPRIM /oracle/app/oradata/CBCD3OSBPRIM /oracle/app/oradata/CBCD3DOCPRIM /oracle/app/oradata/CBCD3SECPRIM /oracle/app/oradata/CBCD3UCMPRIM /oracle/app/oradata/CBCD3SOAPRIM /oracle/app/oradata/CBCD3INTPRIM /oracle/app/oradata/CBCD3CSTPRIM /oracle/app/oradata/CBCD3OBPPRIM /oracle/app/oradata/CBCD3IDMPRIM'
execute "mkdir -p #{dirs_to_create}"
execute "chown -R oracle:oinstall #{dirs_to_create}"

log "Creating databases..."
include_recipe 'environmint-database::default'
log "Databases created successfully."

log "Updating Profiles & Tablespaces for the databases."
include_recipe 'oci-bootstrap::custom-sql-databases'
log "Profiles & Tablespaces updated successfully."

