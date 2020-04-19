require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

_item_code='OCHDB'
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
asset_vars = my_topology_vars[_item_code.downcase]
password_vault_name = my_topology_vars['common']['password_vault_name']

#### Add asset specific code here ####

code = _item_code.downcase
db_version_11='11.2.0.4'

if my_topology_vars['common'].key?('database_version')
  db_version = my_topology_vars['common']['database_version']
else
  db_version='12.1.0.2'
end




default_db_settings=Hash({
  'oracle' => {
    'database' => {
      'datafile_top' => '/oracle/app/oradata',
      'achivelog_top' => '/oracle/app/archive',
      'flashback_top' => '/oracle/app/flashback',
      'databaseList' => [],
      'listenerList' => [{
        'name' => 'LISTENER',
        'port' => 1521,
        'oracle_home' => "/oracle/app/product/db12/#{db_version[0...6]}"
      }]
    }
  }
})
db_settings={}

added_db=[]
# accelerate the build by pushing these to the front :)
db_prio_list=['CBCD3_OCH_PRIM']
# FIXME: make this useful ;)
db_prio_list.each  do |p|
  my_topology_vars.each do |k, a|
    if a.is_a?(Hash)
    Chef::Log.info("Assset: #{a.keys.inspect}")
    if a['database'] and (not added_db.include?(a['database']['service_name'])) and ::File.fnmatch(p, a['database']['service_name'])
      db_hostname=a['database']['scan_address'].gsub('-priv','')
      if not db_settings[db_hostname]
        db_settings[db_hostname]=default_db_settings
      end
      # 12 is default, if unspecified
      if a['db_version']==999 # switch to 11 to force 11g assets onto v11 databases
      db_settings[db_hostname]['oracle']['database']['databaseList'] << Hash({
        'name' => a['database']['service_name'],
        'version' => db_version_11,
        'oracle_base' => "/oracle/app/product/db11",
        'oracle_home' => "/oracle/app/product/db11/#{db_version_11[0...6]}",
        'java_home' => '/oracle/app/product/java11',
        'sysdba_user' => "SYS",
        'sysdba_passwd' => PasswordVault.get_password(password_vault_name, 'database', 'dbsyspassword' ),
        'is_container_db' => false,
        'extra_servicenames' => [ a['database']['service_name'].gsub('_PRIM','_BATCH') ]
      })
      else
      db_settings[db_hostname]['oracle']['database']['databaseList']. << Hash({
        'name' => a['database']['service_name'],
        'version' => db_version,
        'oracle_base' => "/oracle/app/product/db12",
        'oracle_home' => "/oracle/app/product/db12/#{db_version[0...6]}",
        'java_home' => '/oracle/app/product/java12',
        'sysdba_user' => "SYS",
        'sysdba_passwd' => PasswordVault.get_password(password_vault_name, 'database', 'dbsyspassword' ),
        'is_container_db' => false,
        'extra_servicenames' => [ a['database']['service_name'].gsub('_PRIM','_BATCH') ]
      })
      end
      added_db << a['database']['service_name']
    end
    end
  end
end

db_run_list=['recipe[os-common::bootstrap-oracle-public-cloud]','recipe[os-common::bootstrap]', 'recipe[os-common::default]', 'recipe[oracle-common::default]']
db_run_list.insert(-1, "recipe[westpac-ocloud-ldap::default]")
db_run_list.insert(-1, "recipe[oracle-common::configure-oracle-prereqs-database-12c]")
db_run_list.insert(-1, "recipe[environmint-database::default]")
db_run_list.insert(-1, "recipe[obp-environmint-custom::custom-sql-databases]")

db_settings.each do |h, data|
  machine=get_machine(h.split('.')[0],  providerCode=lookup_catalogitem_providerCode(_item_code), providerType=lookup_catalogitem_providerType(_item_code), dnsdomain: "."+h.split('.')[1..-1].join('.'), run_list: db_run_list, attributes: data, memory_gb: 32, cpu: 8)

  machine['blockMap']=[]
  # lets ensure we have swap = ram, which will make java stuff happier
  machine['blockMap'] << Hash({
    'virtualName' => 'swap',
    'type' => 'swap',
    'mountPoint' => 'swap',
    'size' => 64,
    'device' => 'xvdd'
  })
  machine['blockMap'] << Hash({
    'virtualName' => "oracle",
# Removing fixed name of disk, as rebuild fails if the disk is not destroyed quick enough
#    'opc_storage_name' => "#{h.split('.')[0]}-oracle-fast",
    'type' => 'ext4',
    'mountPoint' => "/oracle",
    'size' => 500,
    'device' => "xvdc",
    'opc_storage_type' => '/oracle/public/storage/latency'
  })
  addMachinesToQueue([machine])
end
