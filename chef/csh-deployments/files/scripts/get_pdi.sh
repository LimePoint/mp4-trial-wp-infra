##
## THIS SCRIPT IS RECOMMENDED TO BE EXECUTED ON OBH HOST SERVER
##

if [ $# -lt 1 ];
 then
    echo "Please provide the date list for the Prod-DB-Incr to be deployed";
    echo "Usage =>: $0 <list of space-seperated-Prod-DB-incr-dates in yyyy_mm_dd format>"
    echo "Example : $0 \"2018_06_20 2018_07_12 2018_07_23\" "
    exit;
fi

pdi_home=/oracle/app/binaries/deployments/pdi
FileList=$1
FilePrefix='WPR12_262_PRD_DB_'
SourceURL='https://artifactory1.wpdev.mintpress.io/artifactory/MP-001_CSH-Snapshot/au/com/westpac/csh/R12/Prod_DB_Incr'


if [ -d $pdi_home ]; then
  cd $pdi_home
else
  mkdir -p $pdi_home
  cd $pdi_home
fi

for f in $FileList;
do
  tgtfile=${FilePrefix}${f}.zip
  echo "Downloading ${tgtfile}"
  curl -fSk ${SourceURL}/${tgtfile} -O && unzip -n ${tgtfile} -d $(echo ${tgtfile}|cut -d '.' -f 1)
done

if [ $? != 0 ]; then echo "Either Some or ALL files failed to download. Verify the list provided and try again!!!"; exit 1; fi
