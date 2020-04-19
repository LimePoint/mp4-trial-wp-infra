# Author: Bharat Wadhwa

# Recipe to create the symlinks to redirect the oid logs

Chef::Log.info('Stopping the Services')

Chef::Log.info("The hostname is : #{node.name}")

node_name= "#{node.name}"

ldap_instance_dir = 'oidldap_' + node_name[12,1]
repl_instance_dir = 'oidrepl_' + node_name[12,1]


bash 'Stopping the services 1 ' do
    code <<-EOH
    if [ ! -d /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir} ]  
      then echo "ERROR: The instance home does not exists. [ /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir} ]."  Returning true since this is stop...  
      exit 0 
      fi 

      /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/bin/opmnctl status > /oracle/app/binaries/obpoid/tmp/opmn_stop.tmp 
      cat /oracle/app/binaries/obpoid/tmp/opmn_stop.tmp 
      rm -f /oracle/app/binaries/obpoid/tmp/opmn_stop.tmp
      /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/bin/opmnctl stopall 
      if [ $? -ne 0 ] 
        then echo "ERROR: The instance could not be stopped." 
        exit 1 
      fi 
        echo "The instance has been stopped." 
     
    EOH
end


bash 'Stopping the services 2 ' do
    code <<-EOH
    if [ ! -d /oracle/app/runtime/obpoid/instances/#{repl_instance_dir} ]   
      then echo "ERROR: The instance home does not exists. [ /oracle/app/runtime/obpoid/instances/#{repl_instance_dir} ]."  Returning true since this is stop...   
      exit 0 
    fi 
    /oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/bin/opmnctl status > /oracle/app/binaries/obpoid/tmp/opmn_stop.tmp 
    cat /oracle/app/binaries/obpoid/tmp/opmn_stop.tmp 
    rm -f /oracle/app/binaries/obpoid/tmp/opmn_stop.tmp 
    /oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/bin/opmnctl stopall 
    if [ $? -ne 0 ]  
      then echo "ERROR: The instance could not be stopped."  
      exit 1 
    fi 
    echo "The instance has been stopped."  
     
    EOH
end

bash 'Creating and Moving the log directory ' do
    code <<-EOH

    mkdir -p /oracle/app/logs/obpoid/#{ldap_instance_dir}/diagnostics/
    mkdir -p /oracle/app/logs/obpoid/#{repl_instance_dir}/diagnostics/

    if [ -d "/oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/diagnostics/logs" ] && [ ! -d "/oracle/app/logs/obpoid/#{ldap_instance_dir}/diagnostics/logs" ]
     then
       
        mv /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/diagnostics/logs /oracle/app/logs/obpoid/#{ldap_instance_dir}/diagnostics/logs
      
     else
        echo "/oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/diagnostics/logs directory doesnot exists"
    fi

    if [ -d "/oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/diagnostics/logs" ] && [ ! -d "/oracle/app/logs/obpoid/#{repl_instance_dir}/diagnostics/logs" ]
     then
        mv /oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/diagnostics/logs /oracle/app/logs/obpoid/#{repl_instance_dir}/diagnostics/logs
     else
        echo "/oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/diagnostics/logs directory doesnot exists"
    fi
    EOH
end



Chef::Log.info('Creating the symlink 1')

link "/oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/diagnostics/logs" do
  to "/oracle/app/logs/obpoid/#{ldap_instance_dir}/diagnostics/logs"
  owner 'oracle'
  mode '0755'
end

Chef::Log.info('Creating the symlink 2')


link "/oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/diagnostics/logs" do
  to "/oracle/app/logs/obpoid/#{repl_instance_dir}/diagnostics/logs"
  owner 'oracle'
  mode '0755'
end



bash 'starting the services  1' do
    code <<-EOH
    if [ ! -d /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir} ]  
      then echo "ERROR: The instance home does not exists. [ /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir} ]."  Returning true since this is stop...  
      exit 0 
      fi 

      /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/bin/opmnctl status > /oracle/app/binaries/obpoid/tmp/opmn_start.tmp 
      cat /oracle/app/binaries/obpoid/tmp/opmn_start.tmp 
      rm -f /oracle/app/binaries/obpoid/tmp/opmn_start.tmp
      /oracle/app/runtime/obpoid/instances/#{ldap_instance_dir}/bin/opmnctl startall 
      if [ $? -ne 0 ] 
        then echo "ERROR: The instance could not be stated." 
        exit 1 
      fi 
        echo "The instance has been started." 
     
    EOH
end


bash 'starting the services  2' do
    code <<-EOH
    if [ ! -d /oracle/app/runtime/obpoid/instances/#{repl_instance_dir} ]   
      then echo "ERROR: The instance home does not exists. [ /oracle/app/runtime/obpoid/instances/#{repl_instance_dir} ]."  Returning true since this is stop...   
      exit 0 
    fi 
    /oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/bin/opmnctl status > /oracle/app/binaries/obpoid/tmp/opmn_start.tmp 
    cat /oracle/app/binaries/obpoid/tmp/opmn_start.tmp 
    rm -f /oracle/app/binaries/obpoid/tmp/opmn_start.tmp 
    /oracle/app/runtime/obpoid/instances/#{repl_instance_dir}/bin/opmnctl startall 
    if [ $? -ne 0 ]  
      then echo "ERROR: The instance could not be started."  
      exit 1 
    fi 
    echo "The instance has been started."  
     
    EOH
end

