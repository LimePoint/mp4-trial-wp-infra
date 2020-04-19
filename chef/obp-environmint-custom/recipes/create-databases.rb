# Recipe to create databases

# Install the pre-reqs for DB R12.1
yum_package "oracle-rdbms-server-12cR1-preinstall"

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
  'version' => '12.1.0.2',
  'oracle_base' => "/oracle/app/product/db12",
  'oracle_home' => "/oracle/app/product/db12/12.1.0",
  'java_home' => '/oracle/app/product/java12',
  'sysdba_user' => "SYS",
  'sysdba_passwd' => PasswordVault.get_password(password_vault_name, 'database', 'dbsyspassword' ),
  'is_container_db' => false,
  'extra_servicenames' => db_to_service_mappings[db],
  'patchList' => [
      { 'name'  => 'p26635880_121020_Linux-x86-64', 'aru'   => '26635880' },
      { 'name'  => 'p29158680_12102171017ProactiveBP_Linux-x86-64', 'aru'   => '29158680' }
  ]
})
end

# Override the environmint-database node attributes
node.override['oracle']['database'].tap do | database |
  database['datafile_top'] = '/oracle/app/oradata'
  database['archivelog_top'] = '/oracle/app/archive'
  database['flashback_top'] = '/oracle/app/flashback'
  database['databaseList'] = databaseList
  database['listenerList'] = [
    {
      'name' => 'LISTENER',
      'port' => 1521,
      'oracle_home' => '/oracle/app/product/db/12.1.0'
    }
  ]
end

Chef::Log.info "Creating databases..."
include_recipe 'recipe[environmint-database::default]'
Chef::Log.info "Databases created successfully."

Chef::Log.info "Updating Profiles & Tablespaces for the databases."
include_recipe 'recipe[obp-environmint-custom::custom-sql-databases]'
Chef::Log.info "Profiles & Tablespaces updated successfully."
