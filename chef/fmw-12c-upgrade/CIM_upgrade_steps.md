# Prepare - Upgrade Pre-Reqs
Install JDK 1.8 and Oracle Identity Management 12c at /oracle/app/binaries/<item_code>12c/java and /oracle/app/binaries/<item_code>12c/fmw respectively.

If a new DB is being used for upgrade, have the DB provisioned by the DBA team.

**Shutdown the source CIM 11g Instances** (can use RunTime shutdown plan from original 11g obpcim)

* Update env data bag for target asset obpcim with "release_version": "1.7.0" include new database details if new DB is to be created

* Update the asset JSON in Mintpress server to reflect temporary 12c install path 
* Run the BINARIES stage of the RunTime plan

# CIM Clone

**Source Changes**

Make sure you have backup available 

CIM DirectDB config Update
1)	Login to Enterprise Manager by using the following URL:
2)	https://obpwstg1cim-adm.radtest.wbctestau.westpac.com.au:18101/em
3)	Navigate to Identity and Access, and then oim.
4)	Right-click oim, and navigate to System MBean Browser under Application Defined MBeans.
5)	Navigate to oracle.iam, Application:oim, XMLConfig, Config, XMLConfig.DirectDBConfig, and then DirectDB.
6)	Enter the new value for the URL attribute to reflect the changes to host and port, and then apply the changes.


# OIM Issue - SR Workarround

* After OIM 12c installation completes, go to the below location and update UpgradeMetadata.xml and comment RemoveBIServer Plugin

```
cd /oracle/app/binaries/cim12c/fmw/idm/server/upgrade

Comment the below plugin <!-- -->

vi UpgradeMetadata.xml
<plugin> 
<featureID>RemoveBIServer</featureID> 
<upgradeClass>oracle.iam.oimupgrade.standalone.feature.domainupgrade.RemoveBIServer</upgradeClass> 
<server>both</server> 
<enabled>true</enabled> 
<force>false</force> 
<report>n</report> 
<mode>offline</mode> 
</plugin> 
```

### **1. Run 11g RCU On New Database**
pre-binaries, the 11g RCU is run to create 11g schemas in the new DB if applicable
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::oim-execute-11g-rcu]' -l info
```

* Manual Step
Do DB schema export from source DB into target DB for upgrade.

### **2. Repoint the DB to the New DB Instance & change all the source names to Destination Names**

```
ON Node1
=========
mkdir -p /oracle/app/binaries/12c_upgrade
cd /oracle/app/runtime/obpcim/domains; grep -lIR "obprsvp2cim" | xargs sed -i "s|obprsvp2cim|obprsvp3cim|g";
cd /oracle/app/runtime/obpcim/domains; grep -lIR '/oracle/app/runtime/svp2r/certs/'| xargs sed -i 's|/oracle/app/runtime/svp2r/certs/|/oracle/app/runtime/svp3r/certs/|g';
cd /oracle/app/runtime/obpcim/domains; grep -lIR 'svp2' | xargs sed -i 's|svp2|svp3|g';

cd /oracle/app/binaries/obpcim; grep -lIR 'obprsvp2cim' | xargs sed -i 's|obprsvp2cim|obprsvp3cim|g';
cd /oracle/app/binaries/obpcim/fmw; grep -lIR 'svp2' | xargs sed -i 's|svp2|svp3|g';
mkdir -p /oracle/app/logs/obpcim/obprsvp3cim01/; mkdir -p /oracle/app/logs/obpcim/obprsvp3cim02/; 

ON Node2
=========
mkdir -p /oracle/app/binaries/12c_upgrade
cd /oracle/app/binaries/obpcim; grep -lIR 'obprsvp2cim' | xargs sed -i 's|obprsvp2cim|obprsvp3cim|g';
cd /oracle/app/binaries/obpcim/fmw; grep -lIR 'svp2' | xargs sed -i 's|svp2|svp3|g';
```

```
* (Only on first node ex: obprsvp3cim01)
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::1-migrate-domain]' -l info -F doc > /oracle/app/binaries/12c_upgrade/1-migrate-domain.out &
```

This recipe:
* Updates JDBC data source URLs if a new DB has been created for the upgrade and disables TNSs for DB connections
* now start the weblogic admin and managed servers on new

### **3. Execute the Upgrade Steps**
# Part 1 - Confirm Pre-requisites
* Ensure Binaries are installed in temporary 12c install path
* Ensure target database is provisioned with 11g schemas and data

# Part 2 - Run Upgrade Readiness (Only on first node ex: obprsvp3cim01)
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::2-execute-ua-readiness-check]' -l info -F doc > /oracle/app/binaries/12c_upgrade/2-execute-ua-readiness-check.out &
```

This recipe:
* Runs SQL script to grant DB privs for upgrade
* Regenerates the default-keystore.jks for comatability with java 8
* Runs the FMW upgrade assistant Readiness Check

# Part 3 - Upgrade Database Schemas (Only on first node ex: obprsvp3cim01)
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::3-execute-ua-schema-upgrade]' -l info -F doc > /oracle/app/binaries/12c_upgrade/3-execute-ua-schema-upgrade.out &
```

This recipe:
* Runs the FMW  Upgrade Assitant Schema Upgrade Utility
* Runs 12c RCU to create the STB and IAU schemas required for 12c

# Part 4 - Reconfigure Domain (Only on first node ex: obprsvp3cim01)
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::4-execute-domain-reconfig]' -l info -F doc > /oracle/app/binaries/12c_upgrade/4-execute-domain-reconfig.out &
```

This recipe:
* Removes the SIEMAuditor custom audit provider from the config.xml
* Removes OIM mbean jars from the fmw_11g_home/wlserver_10.3/server/lib/mbeantypes/
* Runs Domain Reconfiguration script to update JDBCSystemResources

# Part 4a - Upgrade Domain Components (Only on first node ex: obprsvp3cim01)
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::4a-oim-ua-domain-upgrade]' -l info -F doc > /oracle/app/binaries/12c_upgrade/4a-oim-ua-domain-upgrade.out &
```

This recipe:
* Runs the FMW upgrade assistant to upgrade the Domain

# Part 5 - Execute post upgrade changes (On Both the nodes ex: obprsvp3cim01 & obprsvp3cim02)
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::5-oim-execute-post-upgrade-changes]' -l info -F doc > /oracle/app/binaries/12c_upgrade/5-oim-execute-post-upgrade-changes.out &
```

This Recipe:
* Copies the nodemanager.properties file from 11g home to 12c home and updates properties as appropriate for 12c
* Updates CustomTrustKeyStoreFileName in WLST_PROPERTIES
* Updates the references for com.oracle.cie.comdev and com.oracle.cie.xmldh libraries in config.xml as per (Doc ID 2535244.1)
* Removes cipherSuites list from LibOVD adapters.os_xml to enable TLS ciphers for Java 8

# Following steps are post-upgrade
# Manual steps  
* Stop all Weblogic servers and NodeManager (should still be down)

* Clean up the all the managed servers
```
rm -rf /oracle/app/runtime/obpcim/domains/obpcim_domain/servers/soa_server* /oracle/app/runtime/obpcim/domains/obpcim_domain/servers/oim_server* /oracle/app/runtime/obpcim/domains/obpcim_domain/servers/bip_server*;
```

# Manual steps
# Part 6 - Start Services 

```
* Start the 12c node manager

export NODEMGR_HOME=/oracle/app/binaries/cim12c/fmw/wlserver/common/nodemanager;
cd /oracle/app/binaries/cim12c/fmw/wlserver/server/bin;
nohup ./startNodeManager.sh & 


* Start Admin Server Manually
cd /oracle/app/runtime/obpcim/domains/obpcim_domain/;
nohup ./startWebLogic.sh &

* Once Admin Server is up we need to update JDBC to XA Driver & Remove the RemoveBIResource (Only on first node ex: obprsvp3cim01)
chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::updateJDBCDriver12c]' -l info -F  doc > /oracle/app/binaries/12c_upgrade/updateJDBCDriver12c.out &
chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::RemoveBIResource]' -l info -F  doc > /oracle/app/binaries/12c_upgrade/RemoveBIResource.out &
```

* Update the SOA Startup Argument from WLS Console to add the following parameter

```
-Dbpm.enabled=true
```
* restart AdminServer.

* Start the SOA server from the console
The SOA logs will show some errors about BPM, that is fine. Ensure that all applications come in active state though.

* Start the OIM server from the console
First startup can be expected to fail, if so start it again.
Ensure all applications are in active state.

* Verify the oracle.idm.ipf library targetting, you will see two different versions of these, one targetting to admin and one targetting to cluster.  -- I got issue with this library compare it with other working environment

* Login into identity console and verify all the users

* Shutdown OIM and SOA servers

* Remove the `-Dbpm.enabled=true` property for SOA server

* Shutdown Admin server and Node manager

# Part 7 - Update FMW & Domain Home (On Both the nodes But Make sure run this on First node and wait for the completion in first node)
```
chef-client  -c $HOME/chef/client.rb -o 'recipe[fmw-12c-upgrade::6-oim-replace-fmw-home]' -l info -F doc > /oracle/app/binaries/12c_upgrade/6-oim-replace-fmw-home.out &
```

This Recipe:
* Backs up the 11g binaries
* Moves the binaries from the temporary 12c install path to the orginal install path
* Updates all references to the temporary 12c install path
* Cleans up the all the managed server directories

# Part 8 - Run Full Online Configuration from MintPress

* Update the obpcim component in the environment data bag file to use the 12c template by defining the appropriate release_version
"release_version": "1.7.0",

* Do **Upload Only** in MintPress Console for the obpcim instance being upgraded, to generate a new JSON with properties relevant for 12c, and open the RunTime project created

* If baselineing is enabled in MintPress (as for Wespac Cloud environments) run Cleanup Baseline plan. If this is not done, the SIEMAuditor resource does not get recreated.

* Run Configure Online plan from MintPress
* Once configure online is successful please make the below change in OIM EM console for the imports to work.

/Domain_obpcim_domain/obpcim_domain > System MBean Browser
oracle.iam > Server:oim_server1 > Application:OIM > XMLConfig > Config > XMLConfig.DiscoveryConfig:Discovery

Update the OimFrontEndURL Attribte value to right address ex: https://obpsvpcim.radtest.wbctestau.westpac.com.au

* Login into Sysadmin Console and update It resources ( EX: OID Server , DBAT_1_4 ) with correct details ( DBName , OID Name , Passwords etc)

# Part 9 - Test
* Ensure all applications are accessible
* Ensure data is visible
* Create and update a user and check if OID gets updated

# Part 10 - Remove BIPLATFORM User
Drop the OBPCIM_BIPLATFORM user from the database
```
Drop user OBPCIM_BIPLATFORM cascade;
Drop tablespace OBPCIM_BIPLATFORM including contents and datafiles;
```

# Part 11 - Cleanup
Remove the backup of the 11g binaries 
```
rm -rf/oracle/app/binaries/obpcim_11g
```