# Recipe to install all Oracle Packages required for FMW
# Reference: https://docs.oracle.com/en/middleware/fusion-middleware/12.2.1.4/sysrs/system-requirements-and-specifications.html#GUID-37C51062-3732-4A4B-8E0E-003D9DFC8C26
#oracle_packages = ['binutils','compat-libcap1','compat-libstdc++-33', 'compat-libstdc++-33','gcc','gcc-c++','glibc','glibc-devel','libaio','libaio-devel','libgcc','libstdc++','libstdc++-devel','libXext','libXtst','openmotif21','sysstat','redhat-lsb','redhat-lsb-core','openssl']
oracle_packages = ['binutils','compat-libcap1','compat-libstdc++-33', 'compat-libstdc++-33','gcc','gcc-c++','glibc','glibc-devel','libaio','libaio-devel','libgcc','libstdc++','libstdc++-devel','libXext','libXtst','sysstat','redhat-lsb','redhat-lsb-core','openssl']

oracle_packages.each do | pkg |
  yum_package pkg do
    arch ['x86_64', 'i686'] 
  end
end

# Package required for LDAP and GIT
yum_package "openldap-clients"
yum_package "git"

# Install nice to haves
yum_package "nc"
yum_package "tree"
yum_package "psmisc"

# Install Packages for net-ldap locally, why are we using locally? Coz Internet is not allowed!
gem_package "net-ldap" do
  source '/oracle/stage/ruby_gems/net-ldap-0.16.2.gem'
end

gem_package "cicphash" do
  source '/oracle/stage/ruby_gems/cicphash-1.1.0.gem'
end

