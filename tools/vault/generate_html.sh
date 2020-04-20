RUBY="/opt/opscode/embedded/bin/ruby"
# create all htmls
# remove zip if it exits
rm -f zipped_csh_vaults_htmls.zip
for i in `ls *.json`
do
if [ "$i" != "mintpress.json" ]
 then
  echo "Generating password html for $i"
  $RUBY csh_decrypt.pwvault.html.rb $i > $i.html
  echo "Generated password html for $i at $i.html"
  zip -u zipped_csh_vaults_htmls.zip $i.html
  rm $i.html
fi
done

echo "Generated zip file at: zipped_csh_vaults_htmls.zip"

