# Inspired from code written by: Serge Rayzman
# This recipe applies the Performance Tuning Changes listed in the below URLs
# https://confluence.srv.westpac.com.au/display/CSH/SVP+Tuning+recommendations+cycle+R1.1
# https://confluence.srv.westpac.com.au/pages/viewpage.action?pageId=190747925
#=================================================================================================

require 'nokogiri'

Chef::Log.info('Configure JPS SSL settings')

environment_name = node.chef_environment.downcase
my_topology_vars = JSON.parse(::File.read("#{__dir__}/../files/data_bags/#{environment_name}_vars.json"))
asset_code = 'obp' + node.name.split('.')[0][-5..-3]
domain_name = my_topology_vars[asset_code]['wls_domain_name']
config_file = "/oracle/app/runtime/#{asset_code}/domains/#{domain_name}/config/fmwconfig/jps-config.xml"

newprops = <<EOXML
<x>
    <property name="authorization_cache_enabled" value="true"/>
    <property name="connection.pool.min.size" value="20"/>
    <property name="connection.pool.max.size" value="40"/>
    <property name="connection.pool.provider.type" value="IDM"/>
    <property name="connection.pool.timeout" value="300000"/>
    <property name="connection.pool.provider.type" value="5"/>
    <property name="oracle.security.jps.policystore.rolemember.cache.type" value="STATIC"/>
    <property name="oracle.security.jps.policystore.rolemember.cache.strategy" value="NONE"/>
    <property name="oracle.security.jps.policystore.rolemember.cache.size" value="100"/>
    <property name="oracle.security.jps.policystore.policy.lazy.load.enable" value="true"/>
    <property name="oracle.security.jps.policystore.policy.cache.strategy" value="NONE"/>
    <property name="oracle.security.jps.policystore.policy.cache.size" value="1000000"/>
    <property name="oracle.security.jps.policystore.refresh.enable" value="true"/>
    <property name="oracle.security.jps.policystore.refresh.purge.timeout" value="1296000000"/>
    <property name="oracle.security.jps.ldap.policystore.refresh.interval" value="6000000"/>
    <property name="oracle.security.jps.policystore.rolemember.cache.warmup.enable" value="true"/>
</x>
EOXML

ruby_block "Enable Authorization Cache" do
    block do
        Chef::Log.info("Inspecting #{config_file} ")

        doc = Nokogiri::XML(File.open(config_file))
        newnodes = Nokogiri::XML::Reader(newprops)

        dbprops = doc.at_xpath("//tns:propertySet[@name='props.db.1']", 'tns' => 'http://xmlns.oracle.com/oracleas/schema/11/jps-config-11_1.xsd')
        if dbprops.nil?
            Chef::Log.info("PropertySet props.db.1 is not configured")
        else
            ## Add New Property
            newnodes.each do |newnode|
                if newnode.name=='property' && newnode.attribute_at(0).to_s.include?("authorization_cache_enabled")
                    dbprops.add_child newnode.outer_xml.to_s + "\n" ## add the newnode as a child node.
                    #Get the location of the other node to be updated
                    srvcInst = doc.at_xpath("//tns:serviceInstance[@name='pdp.service']", 'tns' => 'http://xmlns.oracle.com/oracleas/schema/11/jps-config-11_1.xsd')
                    if srvcInst.nil?
                        Chef::Log.info("PDP service Instance is not configured")
                    else
                    srvcInst.add_child newnode.outer_xml.to_s + "\n" ## add the newnode as a child node.
                    end
                end
            end
        end
        File.write(config_file, doc.to_xml)
    end
    only_if { File.exists?(config_file)  && File.readlines(config_file).grep(/authorization_cache_enabled/).empty? }
end

ruby_block "Add Connection Pool properties" do
    block do
        Chef::Log.info("Inspecting #{config_file} ")

        doc = Nokogiri::XML(File.open(config_file))
        newnodes = Nokogiri::XML::Reader(newprops)

        dbprops = doc.at_xpath("//tns:propertySet[@name='props.db.1']", 'tns' => 'http://xmlns.oracle.com/oracleas/schema/11/jps-config-11_1.xsd')
        if dbprops.nil?
            Chef::Log.info("PropertySet props.db.1 is not configured")
        else
            ## Add New Property
            newnodes.each do |newnode|
                if newnode.name=='property' && newnode.attribute_at(0).to_s.include?("connection.pool")
                    dbprops.add_child newnode.outer_xml.to_s + "\n" ## add the newnode as a child node.
                    #Get the location of the other node to be updated
                    srvcInst = doc.at_xpath("//tns:serviceInstance[@name='pdp.service']", 'tns' => 'http://xmlns.oracle.com/oracleas/schema/11/jps-config-11_1.xsd')
                    if srvcInst.nil?
                        Chef::Log.info("PDP service Instance is not configured")
                    else
                    srvcInst.add_child newnode.outer_xml.to_s + "\n" ## add the newnode as a child node.
                    end
                end
            end
        end
        File.write(config_file, doc.to_xml)
    end
    only_if { File.exists?(config_file)  && File.readlines(config_file).grep(/connection\.pool\./).empty? }
end

ruby_block "Add JPS policystore properties" do
    block do
        Chef::Log.info("Inspecting #{config_file} ")

        doc = Nokogiri::XML(File.open(config_file))
        newnodes = Nokogiri::XML::Reader(newprops)

        dbprops = doc.at_xpath("//tns:propertySet[@name='props.db.1']", 'tns' => 'http://xmlns.oracle.com/oracleas/schema/11/jps-config-11_1.xsd')
        if dbprops.nil?
            Chef::Log.info("PropertySet props.db.1 is not configured")
        else
            ## Add New Property
            newnodes.each do |newnode|
                if newnode.name=='property' && newnode.attribute_at(0).to_s.include?("policystore")
                    dbprops.add_child newnode.outer_xml.to_s + "\n" ## add the newnode as a child node.
                    #Get the location of the other node to be updated
                    srvcInst = doc.at_xpath("//tns:serviceInstance[@name='pdp.service']", 'tns' => 'http://xmlns.oracle.com/oracleas/schema/11/jps-config-11_1.xsd')
                    if srvcInst.nil?
                        Chef::Log.info("PDP service Instance is not configured")
                    else
                    srvcInst.add_child newnode.outer_xml.to_s + "\n" ## add the newnode as a child node.
                    end
                end
            end
        end
        File.write(config_file, doc.to_xml)
    end
    only_if { File.exists?(config_file)  && File.readlines(config_file).grep(/oracle\.security\.jps\.policystore/).empty? }
end
