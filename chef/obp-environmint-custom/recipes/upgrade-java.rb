# Author: Harsha Gurram

# This recipe upgrades JAVA for OIM;CIM and JRE for DOC
# This can be run over and over again.

bash 'Upgrade JAVA to 1.7.0_181' do
    code <<-EOH
    if [ -d "/oracle/app/binaries/obpoim" ]; then
        cd /oracle/app/binaries/obpoim
        JAVA_VERSION=$(/oracle/app/binaries/obpoim/java/bin/java -version 2>&1 |grep 'java.version'|awk '{print $3}'|sed 's/"//g')
        if [ x$JAVA_VERSION = x1.7.0_181 -o 1.7.0_181 = unknown ]; then
            /oracle/app/binaries/obpoim/java/bin/java -version
            echo 'Already upgraded java exists'
            exit $? ;
        else
            echo 'Backing up existing java'
            mv java java.mintbkp.$(date +%s)
            tar -xzf /oracle/stage/jdk/jdk-7u181-linux-x64.tar.gz
            mv jdk1.7.0_181 java
            echo 'Java upgraded to:'
            /oracle/app/binaries/obpoim/java/bin/java -version
        fi
    elif [ -d "/oracle/app/binaries/obpcim" ]; then
        cd /oracle/app/binaries/obpcim
        JAVA_VERSION=$(/oracle/app/binaries/obpcim/java/bin/java -version 2>&1 |grep 'java.version'|awk '{print $3}'|sed 's/"//g')
        if [ x$JAVA_VERSION = x1.7.0_181 -o 1.7.0_181 = unknown ]; then
            /oracle/app/binaries/obpcim/java/bin/java -version
            echo 'Already upgraded java exists'
            exit $? ;
        else
            echo 'Backing up existing java'
            mv java java.mintbkp.$(date +%s)
            tar -xzf /oracle/stage/jdk/jdk-7u181-linux-x64.tar.gz
            mv jdk1.7.0_181 java
            echo 'Java upgraded to:'
            /oracle/app/binaries/obpcim/java/bin/java -version
        fi
    fi
    EOH
    user 'oracle'
    group 'oinstall'
end

jre_install_dir='/oracle/app/binaries/obpdoc/fmw/odee_12/documaker'

bash 'Upgrade Documaker JRE to 1.8.0_172' do
    code <<-EOH
    if [ -d "/oracle/app/binaries/obpdoc" ]; then
        cd #{jre_install_dir}
        JAVA_VERSION=$(/oracle/app/binaries/obpdoc/fmw/odee_12/documaker/jre/bin/java -version 2>&1 |grep 'java.version'|awk '{print $3}'|sed 's/"//g')
        if [ x$JAVA_VERSION = x1.8.0_172 -o 1.8.0_172 = unknown ]; then
            /oracle/app/binaries/obpdoc/fmw/odee_12/documaker/jre/bin/java -version
            echo 'Already upgraded jre exists'
            exit $? ;
        else
            echo 'Backing up existing jre'
            mv jre jre.mintbkp.$(date +%s)
            tar -xzf /oracle/stage/jdk/jre_doc-8u172.tar.gz
            /oracle/app/binaries/obpdoc/fmw/odee_12/documaker/jre/bin/java -version
        fi
    fi
    EOH
    user 'oracle'
    group 'oinstall'
end
