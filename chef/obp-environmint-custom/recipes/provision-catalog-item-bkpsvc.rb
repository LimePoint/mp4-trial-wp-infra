require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='BKPSVC'
return unless node.run_state[_item_code]

environment_name = node.run_state['orchestration_metadata']['launchDetails']['environment']['name'].downcase
environment_code = environment_name.strip.tr('.','').tr('_','').tr('-','').tr(' ','')

##### Load databag variables and merge them with SC properties -- #####
##### Merge _under_, rather than _over_, so that the console properties take precidence ####
#
Chef::Log.info("ENV: #{environment_name}")

global_properties = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
node.run_state[_item_code.upcase]['properties']=global_properties.to_h.deep_merge!(node.run_state[_item_code.upcase]['properties']).insensitive

my_topology_vars = topology_vars(_item_code)
password_vault_name = my_topology_vars['common']['password_vault_name']

#### Add asset specific code here ####

if my_topology_vars['common'].key?('database_version')
  db_version = my_topology_vars['common']['database_version']
else
  db_version='12.1.0.2'
end

db_hostname="obpc#{environment_code}bkpsrv"
db_settings=Hash({
  'oracle' => {
    'database' => {
      'datafile_top' => '/oracle/app/oradata',
      'achivelog_top' => '/oracle/app/archive',
      'flashback_top' => '/oracle/app/flashback',
      'databaseList' => [],
      'listenerList' => [{
        'name' => 'LISTENER_RCAT',
        'port' => 1521,
        'oracle_home' => "/oracle/app/product/db/#{db_version[0...6]}"
      }]
    }
  }
})

# accelerate the build by pushing these to the front :)
db_settings['oracle']['database']['databaseList']. << Hash({
    'name' => 'RCATDB',
    'version' => db_version,
    'oracle_base' => "/oracle/app/product/db",
    'oracle_home' => "/oracle/app/product/db/#{db_version[0...6]}",
    'java_home' => '/oracle/app/product/java',
    'sysdba_user' => "SYS",
    'sysdba_passwd' => PasswordVault.get_password(password_vault_name, 'rcatdb', 'dbsyspassword' ),
    'is_container_db' => false
})
Chef::Log.info("Assset: #{db_settings.inspect}")

db_run_list=['recipe[os-common::bootstrap-oracle-public-cloud]','recipe[os-common::bootstrap]', 'recipe[os-common::default]', 'recipe[oracle-common::default]']
db_run_list.insert(-1, "recipe[westpac-ocloud-ldap::default]")
db_run_list.insert(-1, "recipe[oracle-common::configure-oracle-prereqs-database-12c]")
db_run_list.insert(-1, "recipe[obp-environmint-customn::configure-backups]")
#db_run_list.insert(-1, "recipe[environmint-database::default]")
#db_run_list.insert(-1, "recipe[obp-environmint-custom::custom-sql-databases]")

  machine=get_machine(db_hostname, providerCode=lookup_catalogitem_providerCode(_item_code), providerType=lookup_catalogitem_providerType(_item_code), dnsdomain: lookup_catalogitem_property(_item_code, 'dns_domain').downcase, run_list: db_run_list, attributes: db_settings, memory_gb: 16, cpu: 4)

  machine['blockMap']=[]
  # lets ensure we have swap = ram, which will make java stuff happier
  machine['blockMap'] << Hash({
    'virtualName' => 'swap',
    'type' => 'swap',
    'mountPoint' => 'swap',
    'size' => 16,
    'device' => 'xvdd'
  })
  machine['blockMap'] << Hash({
    'virtualName' => "oracle",
# Removing fixed name of disk, as rebuild fails if the disk is not destroyed quick enough
#    'opc_storage_name' => "#{h.split('.')[0]}-oracle-fast",
    'type' => 'ext4',
    'mountPoint' => "/oracle",
    'size' => 300,
    'device' => "xvdc",
    'opc_storage_type' => '/oracle/public/storage/latency'
  })
  machine['blockMap'] << Hash({
    'virtualName' => "backups",
    'type' => 'ext4',
    'mountPoint' => "/backups",
    'size' => 1024,
    'device' => "xvde",
    'opc_storage_type' => '/oracle/public/storage/latency'
  })
  addMachinesToQueue([machine])
