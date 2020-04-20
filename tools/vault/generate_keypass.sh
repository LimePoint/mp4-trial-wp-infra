RUBY="/opt/opscode/embedded/bin/ruby"
# create all xmls
# remove zip if it exits
rm -f zipped_csh_vaults_xmls.zip
for i in `ls *.json`
do
if [ "$i" != "mintpress.json" ]
 then
  echo "Generating password xml for $i"
  $RUBY csh_decrypt.pwvault.xml.rb $i > $i.xml
  echo "Generated password xml for $i at $i.xml"
  zip -u zipped_csh_vaults_xmls.zip $i.xml
  rm $i.xml
fi
done

echo "Generated zip file at: zipped_csh_vaults_xmls.zip"

