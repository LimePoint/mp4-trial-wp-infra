# Part 1 -  11g Domain Migration and Upgrade Readiness

### **Step 1. Create 11g RCU Schemas On New Database**
* Generate a new build plan with env_vars updated pointing to new DB instance, but **not** the release_version.
* Run RCU Plan to create 11g schemas in new DB instance

### **Step2. Install 12c Binaries in temp location**
* Temporarily update 'obpipm-1.7.0.json.erb' template to point to 'temp binaries' location of '/oracle/app/binaries/ipm12c'
* Update env_vars pointing to new DB instance and the **release_version** set to '1.7.0'
* Generate new build plan 
* Run Binaries plan to install 12c binaries in temp location
* Revert the 'temp binaries' location change and regenerate new build plan. This should be used to run Full Online at the end of Upgrade.


### **Step 3. DB Schema Migration**
* Pre - TVT that all servers are running and in Healthy State with no issues and able to retrieve data by searching and opening documents. 
  _Take Screenshots of the TVT_
* Shutdown Source Domain
* Get the DBA Team to do DB schema export from source DB and import into target DB.

NOTE: VM Migration -- TBD 

### **Step 4. Repoint the Domain to the New DB Instance**
* Run below commands across all nodes in the domain.
```
mkdir -p /oracle/app/binaries/12c_upgrade

chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::1-migrate-domain]' -l info -F doc > /oracle/app/binaries/12c_upgrade/1-migrate-domain.out &

```
This recipe:
* Updates JDBC data source URLs to point to new DB and disables SSL for DB connections

### **Step 5. PRE TVT**


_Verification: Start the domain and TVT that all servers have come up with no issues and able to retrieve data by searching and opening documents._
			   _Take Screenshots of the TVT_

* Shutdown the domain and cleanup the domains folder for any unnecessary backups (like tmp/cache/core files etc)


# Part 2 -  Execute Upgrade Steps

### **Step 1. Run Upgrade Readiness**

* Execute below command

```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::2-execute-ua-readiness-check]' -l info -F doc > /oracle/app/binaries/12c_upgrade/2-execute-ua-readiness-check.out &
```

This recipe:
* Out puts the status of Shcema version registry and reports for any INVALID Objects
* Runs the FMW upgrade assistant Readiness Check

_Verification: Review the log file for schema version and # of invalid objects(should be 0 ) as well as the readiness check report success. Proceed only if all are verified successfully._

### **Step 2. Upgrade Database Schemas**

* Execute below command

```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::3-execute-ua-schema-upgrade]' -l info -F doc > /oracle/app/binaries/12c_upgrade/3-execute-ua-schema-upgrade.out &
```

This recipe:
* Runs the FMW  Upgrade Assitant Schema Upgrade Utility and creates additional auxillary schemas required for 12c.

_Verification: Review the log file verifying success of schema upgrade as well as schema versions. Proceed only if all are verified successfully._

### **Step 3. Reconfigure Domain**

* Execute below command

```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::4-execute-domain-reconfig]' -l info -F doc > /oracle/app/binaries/12c_upgrade/4-execute-domain-reconfig.out &
```

This recipe:
* Removes the SIEMAuditor custom audit provider from the config.xml
* Runs Domain Reconfiguration script.

_Verification: Review the log file verifying success of Domain Reconfiguration. Proceed only if verified successfully._


### **Step 4. Execute post upgrade changes**

* Execute below command
	**NOTE:** Execute this recipe on every node. 

```
mkdir -p /oracle/app/binaries/12c_upgrade;
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::5-obpipm-execute-post-upgrade-changes]' -l info -F doc > /oracle/app/binaries/12c_upgrade/5-obpipm-execute-post-upgrade-changes.out &
```

This Recipe:
* Configures 12c NodeManager properties
* Update filepaths in UCM Vault Directory
* Pack Unpack Domain
* Remove 11g specific unnecessary configuration files after unpack
* Backs up the 11g binaries
* Moves the binaries from the temporary 12c install path to the orginal install path
* Updates all references to the temporary 12c install path

_Verification: Review the log files for any errors_


### **Step 5. Post TVT**

* Start Nodemanager
```
 export NODEMGR_HOME=/oracle/app/binaries/obpipm/fmw/wlserver/common/nodemanager;
  cd /oracle/app/binaries/obpipm/fmw/wlserver/server/bin;
  nohup ./startNodeManager.sh & 
```

* Start Admin Server
```
nmConnect('weblogic','<weblogic_password>','<admin_host_name>','16001','obpipm_domain','/oracle/app/runtime/obpipm/domains/obpipm_domain','SSL')
```

* Add SSL Param to managed servers startup args from console
```
-Dweblogic.ssl.SSLv2HelloEnabled=false
```

* Run recipe  ( TBD if actually required )
```
chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::update-wls-ldap-adapters]' -l info
```
* Restart Admin

* Start up Managed Servers from wls console and verify imaging and cs console logins; verify data by searching  and viewing documents.
  _TVT the same data screenshots take in Pre-TVT step_

### **Step 6. Execute Full Online**

* Shutdown the domain
* Execute the Full-Online Plan from the build plan generated in Part 1: Step 2.
* Restart The Domain
* TVT




