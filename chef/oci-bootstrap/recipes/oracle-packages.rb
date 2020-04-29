# Recipe to install all Oracle Packages required for FMW
# Reference: https://docs.oracle.com/en/middleware/fusion-middleware/12.2.1.4/sysrs/system-requirements-and-specifications.html#GUID-37C51062-3732-4A4B-8E0E-003D9DFC8C26
oracle_packages = ['binutils','compat-libcap1','compat-libstdc++-33', 'compat-libstdc++-33','gcc','gcc-c++','glibc','glibc-devel','libaio','libaio-devel','libgcc','libstdc++','libstdc++-devel','libXext','libXtst','sysstat','redhat-lsb','redhat-lsb-core','openssl','ksh','xorg-x11-xauth']

oracle_packages.each do | pkg |
  yum_package pkg do
    arch 'x86_64'
  end
  # Run 64 and 32 bits separate coz chef just checks one, if it finds one, it will not install the other arch
  # Marking ignore failure true on 32b coz not all of them have one
  yum_package pkg do
    arch 'i686' 
    ignore_failure true
  end
end

# Package required for LDAP and GIT
yum_package "openldap-clients"
yum_package "git"

# Install nice to haves
yum_package "nc"
yum_package "tree"
yum_package "psmisc"
yum_package "htop" unless node['platform_version'].to_i <= 7

# Install the rdbms package if it is a db node
if node.name.split(".")[0][-2..-1] == 'db'
  yum_package "oracle-rdbms-server-12cR1-preinstall"
end

