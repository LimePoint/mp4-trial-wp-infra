echo "Fetching vault list..."
vault_list=`knife data bag show password_vault`
echo "Vault list:\n $vault_list"
for i in $vault_list
do
  echo "Backing up vault: $i"
  if [ "${i}" == "mintpress" ]; then
    knife data bag show password_vault $i -F j > ${i}_`hostname`.json
  else
    knife data bag show password_vault $i -F j > ${i}.json
  fi
  echo "Backup successfull."
done
