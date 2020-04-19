## Steps to Migrate OID data from 11g to 12c

>**NOTE**: All steps are to be performed as **`oracle`** user.

### Phase #1 : Backup the 11g data 

1. Backup all the data for **`basedn="dc=westpac,dc=com,dc=au"`** to a ldif file using the **`ldifwrite`** command. 

    >**NOTE**: When Prompted for OID Password key-in the ODS schema password.

    ```
    $ export ORACLE_HOME=/oracle/app/binaries/obpoid/fmw/idm
    $ export ORACLE_INSTANCE=/oracle/app/runtime/obpoid /instances/oidldap_1
    $ $ORACLE_HOME/ldap/bin/ldifwrite connect=OIDDB basedn="dc=westpac,dc=com,dc=au" ldiffile=/tmp/oid_full_ldfifwrite_westpac.ldif
    ```

    ###### Sample OUTPUT

    ---
    ```
    Enter OID Password ::

    ------------------------------------------------------------
    Reading entries under BaseDN "dc=westpac,dc=com,dc=au"...
    -------------------------------------------------------------

    ------------------------------------------------------------
    772 Entries are written to "/tmp/oid_full_ldfifwrite_westpac.ldif".
    ------------------------------------------------------------
    ```
    ---

2. Review the output as well as the logfile **`ldifwrite.log`** for any errors
 
    ```
    $ cd /oracle/app/runtime/obpoid/instances/oidldap_1/diagnostics/logs/OID/tools/
    $ more ldifwrite.log
    ```

3. Copy the generated ldif file **`/tmp/oid_full_ldfifwrite_westpac.ldif`** to a staging location.
4. Repeat the same steps for CID export as well, 
sample commands are below

    ```
    $ export ORACLE_HOME=/oracle/app/binaries/obpcid/fmw/idm
    $ export ORACLE_INSTANCE=/oracle/app/runtime/obpcid/instances/oidldap_1

    $ $ORACLE_HOME/ldap/bin/ldifwrite connect=OIDDB basedn="dc=westpac,dc=com,dc=au" ldiffile=/tmp/cid_full_ldfifwrite_westpac.ldif

    $ cd /oracle/app/runtime/obpcid/instances/oidldap_1/diagnostics/logs/OID/tools/
    $ more ldifwrite.log
    ```

### Phase #2: Load the backups from 11g to 12C 

1. Stop all the components in OID and CID.
    > **NOTE:**
    >   1. In dual a node environments we have multiple components.
    >   2. All commands below are for **`obpcid`**. Make appropriate changes to command paths for **`obpoid`**.

    ```
    $ export ORACLE_HOME=/oracle/app/binaries/obpcid/fmw
    $ export DOMAIN_HOME=/oracle/app/runtime/obpcid/domains/obpcid_domain
    $ cd $DOMAIN_HOME/bin
    $ $DOMAIN_HOME/bin/stopComponent.sh oid1
    $ $DOMAIN_HOME/bin/stopComponent.sh oidrepl1
    ```
2. Bulk delete all the entries using the below command
    ```
    $ $ORACLE_HOME/ldap/bin/bulkdelete connect=OIDDB basedn="dc=westpac,dc=com,dc=au" cleandb="TRUE"
    ```

3. On successful deletion, load the ldif files from **Phase #1**

    ```
   $ $ORACLE_HOME/ldap/bin/bulkload connect=OIDDB check="TRUE" generate="TRUE" restore="TRUE" file=/oracle/app/binaries/cim_upgrade/cid_full_ldfifwrite_westpac.ldif
    ```
4. Verify if we have any bad entries left after load

    ```
   $ more /oracle/app/runtime/obpcid/domains/obpcid_domain/tools/OID/load/badentry.ldif
    ```

5. Finally load data into the target.
    ```
   $ $ORACLE_HOME/ldap/bin/bulkload connect=OIDDB load="TRUE"
    ```

### Phase #3: Load the OID[CID] content

1. Logon to the OID VM as **`oracle`** user and execute the **`obp-environmint-custom::oid-content-load`** recipe as illustrated
    ```
    chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::oid-content-load]' -l info
    ```
2. Logon to the CID VM as **`oracle`** user and execute the **`obp-environmint-custom::cid-content-load`** recipe as illustrated
    ```
    chef-client -c $HOME/chef/client.rb -o 'recipe[obp-environmint-custom::cid-content-load]' -l info
    ```
