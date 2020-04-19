dataceter_id=$1
source_env=$2
target_env=$3
current_node=$4
cd /oracle/app/binaries/runtime/obpipm/domains/obpipm_domain/servers;
find -name tmp -o -name cache -o -name logs -o -name adr -type d | xargs rm -rf;

echo "Updating in path - /oracle/app/binaries/obpipm "
cd /oracle/app/binaries/obpipm;
echo "grep -lIR \"obp$dataceter_id$source_env$current_node\" | xargs sed -i \"s|obp$dataceter_id$source_env$current_node|obp$dataceter_id$target_env$current_node|g\""
grep -lIR "obp$dataceter_id$source_env$current_node" | xargs sed -i "s|obp$dataceter_id$source_env$current_node|obp$dataceter_id$target_env$current_node|g"

echo "grep -lIR \"/oracle/app/runtime/$source_env$dataceter_id/certs/\" | xargs sed -i \"s|/oracle/app/runtime/$source_env$dataceter_id/certs/|/oracle/app/runtime/$target_env$dataceter_id/certs/|g\""

grep -lIR "/oracle/app/runtime/$source_env$dataceter_id/certs/" | xargs sed -i "s|/oracle/app/runtime/$source_env$dataceter_id/certs/|/oracle/app/runtime/$target_env$dataceter_id/certs/|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ipm.jks\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ipm.jks|obp$dataceter_id"$target_env"ipm.jks|g\""
grep -lIR "obp$dataceter_id"$source_env"ipm.jks" | xargs sed -i "s|obp$dataceter_id"$source_env"ipm.jks|obp$dataceter_id"$target_env"ipm.jks|g"

#################

echo "Updating in path - /oracle/app/binaries/runtime "
cd /oracle/app/binaries/runtime;

echo "grep -lIR \"obp$dataceter_id"$source_env"ipm01\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ipm01|obp$dataceter_id"$target_env"ipm01|g\""

grep -lIR "obp$dataceter_id"$source_env"ipm01" | xargs sed -i "s|obp$dataceter_id"$source_env"ipm01|obp$dataceter_id"$target_env"ipm01|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ipm02\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ipm02|obp$dataceter_id"$target_env"ipm02|g\""
grep -lIR "obp$dataceter_id"$source_env"ipm02" | xargs sed -i "s|obp$dataceter_id"$source_env"ipm02|obp$dataceter_id"$target_env"ipm02|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ucm01\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ucm01|obp$dataceter_id"$target_env"ucm01|g\""
grep -lIR "obp$dataceter_id"$source_env"ucm01" | xargs sed -i "s|obp$dataceter_id"$source_env"ucm01|obp$dataceter_id"$target_env"ucm01|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ucm02\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ucm02|obp$dataceter_id"$target_env"ucm02|g\""
grep -lIR "obp$dataceter_id"$source_env"ucm02" | xargs sed -i "s|obp$dataceter_id"$source_env"ucm02|obp$dataceter_id"$target_env"ucm02|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ipm-padm\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ipm-padm|obp$dataceter_id"$target_env"ipm-padm|g\""

grep -lIR "obp$dataceter_id"$source_env"ipm-padm"| xargs sed -i "s|obp$dataceter_id"$source_env"ipm-padm|obp$dataceter_id"$target_env"ipm-padm|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ipm-adm\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ipm-adm|obp$dataceter_id"$target_env"ipm-adm|g\""

grep -lIR "obp$dataceter_id"$source_env"ipm-adm"| xargs sed -i "s|obp$dataceter_id"$source_env"ipm-adm|obp$dataceter_id"$target_env"ipm-adm|g"

echo "grep -lIR \"obp"$source_env"oid\" | xargs sed -i \"s|obp"$source_env"oid|obp"$target_env"oid|g\""

grep -lIR "obp"$source_env"oid"| xargs sed -i "s|obp"$source_env"oid|obp"$target_env"oid|g"

echo "grep -lIR \"/oracle/app/runtime/"$source_env"$dataceter_id/certs/\" | xargs sed -i \"s|/oracle/app/runtime/"$source_env"$dataceter_id/certs/|/oracle/app/runtime/"$target_env"$dataceter_id/certs/|g\""

grep -lIR "/oracle/app/runtime/"$source_env"$dataceter_id/certs/"| xargs sed -i "s|/oracle/app/runtime/"$source_env"$dataceter_id/certs/|/oracle/app/runtime/"$target_env"$dataceter_id/certs/|g"

echo "grep -lIR \"/oracle/app/runtime/obpipm/"$source_env"$dataceter_id/ucm\" | xargs sed -i \"s|/oracle/app/runtime/obpipm/"$source_env"$dataceter_id/ucm|/oracle/app/runtime/obpipm/"$target_env"$dataceter_id/ucm|g\""
grep -lIR "/oracle/app/runtime/obpipm/"$source_env"$dataceter_id/ucm" | xargs sed -i "s|/oracle/app/runtime/obpipm/"$source_env"$dataceter_id/ucm|/oracle/app/runtime/obpipm/"$target_env"$dataceter_id/ucm|g"

echo "grep -lIR \"obp$dataceter_id"$source_env"ipm.jks\" | xargs sed -i \"s|obp$dataceter_id"$source_env"ipm.jks|obp$dataceter_id"$target_env"ipm.jks|g\""
grep -lIR "obp$dataceter_id"$source_env"ipm.jks" | xargs sed -i "s|obp$dataceter_id"$source_env"ipm.jks|obp$dataceter_id"$target_env"ipm.jks|g"

echo "mkdir -p /oracle/app/logs/obpipm/obp$dataceter_id$source_env$current_node"
mkdir -p /oracle/app/logs/obpipm/obp$dataceter_id$source_env$current_node
mkdir -p /oracle/app/binaries/12c_upgrade
