## This is a temporary resource that I [rb] had to write, why?
## We were using the ldap_entry from the community ldap cookbook
## It stopped working for me with this error: NameError : uninitialized constant Chef::Resource::ldap_entry
## It is something to do with how Chef works with newer versions, anyways, it was easier to just write a resource
## There are few things to do in this resource:
## TODO: it is hardcoded to use SSL
## TODO: it is not case insensitive, e.g. dn is different to DN 

resource_name :ldap_entry

property :ldap_entry, String, name_property: true
property :host, String
property :port, Integer
property :use_tls, [TrueClass, FalseClass]
property :credentials, Hash
property :attributes, Hash


# Action to create the LDAP entry
action :create do
  require 'net/ldap'
  ldap = Net::LDAP.new(
    host: new_resource.host,
    port: new_resource.port, 
    auth: {method: :simple, username: new_resource.credentials['bind_dn'], password: new_resource.credentials['password'] }, encryption: {method: :simple_tls}
  )

  dn = new_resource.ldap_entry
  #attr = {
  #        #cn: dn.split(',')[0].sub('cn=',''),
  #        objectclass: new_resource.attributes[:objectClass] 
  #        }
  attr = new_resource.attributes

  if !ldap.search(base: dn)
    if ldap.add(dn: dn, attributes: attr)
      Chef::Log.info("Successfully added entry [#{new_resource.ldap_entry}]")
    else
      Chef::Log.info("Adding Entry failed [#{new_resource.ldap_entry}]")
      raise
    end
  else
    if attr[:sudoHost]
      ldap.add_attribute dn, :sudoHost, attr[:sudoHost]
    else
      Chef::Log.info("Entry [#{new_resource.ldap_entry}] already exists. Skipping.")
    end
  end
end

# Action to delete the entry
action :delete do
  require 'net/ldap'
  ldap = Net::LDAP.new(
    host: new_resource.host,
    port: new_resource.port, 
    auth: {method: :simple, username: new_resource.credentials['bind_dn'], password: new_resource.credentials['password'] }, encryption: {method: :simple_tls}
  )

  dn = new_resource.ldap_entry
  if ldap.search(base: dn)
    # Match found delete
    if ldap.delete(dn: dn)
      Chef::Log.info("Successfully deleted entry [#{new_resource.ldap_entry}]")
    else
      Chef::Log.info("Could not delete entry [#{new_resource.ldap_entry}]")
      raise
    end
  else
    Chef::Log.info("Entry [#{new_resource.ldap_entry}] not found. Skipping.")
  end
end
