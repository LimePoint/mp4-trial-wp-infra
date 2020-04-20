#!/bin/bash
HELP_STR="Usage: $0 <Limepoint-Cont-Delivery-Home> <List of Environments> <Orchestration Home> <Console User> <Console Pwd> <ConsolePwd"
deploy-console() {
  echo "The Orchestration Key ::$1 "
  echo "The Action      :: $2"
  echo "Console User    :: $3"
  echo "Console Pwd     :: $4"
  echo "Console API Url :: $5"
  echo " <<<<DEPLOY>>>> "
  json_for_post="{\"uuid\": \"$1\", \"actionCode\": \"$2\", \"itemCode\": \"OBPDEPS\" }"
  response=`curl --write-out %{http_code} --user "$3:$4" "$5" -d "$json_for_post" -H "Content-Type: application/json"`
  echo "Reponse from the Request $response"
  return 0
}

[ "$1" = "" ] && echo "Expecting <Limepoint-Cont-Delivery-Home> ::  $HELP_STR" && exit 1
[ "$2" = "" ] && echo "Expecting <List of Environments> :: $HELP_STR" && exit 1
[ "$3" = "" ] && echo "Expecting <Orchestration Home> :: $HELP_STR" && exit 1
[ "$4" = "" ] && echo "Expecting <Console User> :: $HELP_STR" && exit 1
[ "$5" = "" ] && echo "Expecting <Console Pwd> :: $HELP_STR" && exit 1
[ "$6" = "" ] && echo "Expecting <Console URL> :: $HELP_STR" && exit 1
echo "Continous Delivery Home: $1"
echo "Environment List : $2"
echo "Orchestration Key Home : $3"
echo "Console User : $4"
echo "Console PWD : $5"
echo "Console URL : $6"
CD_HOME=$1
list=${2^^}
ORCH_KEY_HOME=$3

IFS=', ' read -r -a array <<< "$list"
echo "Executing from this directory :: Must be under Git Manifest Repo" 
pwd
echo "Listing from this directory ::" 

ls -la
for selectedenv in "${array[@]}"
do
      
      if [ -e "./$selectedenv/manifest.json" ];then
        echo "Okay ... lets start probing this env $selectedenv"
        echo "================================================="
        currentContent="$(git log -n 1  ./$selectedenv/manifest.json|awk 'FNR == 1 {print $2}')"
        echo "Current Content => $currentContent"
        previousContent=`cat $CD_HOME/$selectedenv-manifest-last-commit.log`  
        echo "Previous Content => $previousContent"
        echo $currentContent > $CD_HOME/$selectedenv-manifest-last-commit.log
        if [ "$previousContent" != ""  -a  "$currentContent" != "$previousContent" ]
        then
          echo "Change in Commit::Call the deploy action here ....."

          catalog="$ORCH_KEY_HOME/obpdeps.${selectedenv,,}"".json"
          if [ -e "$catalog" ];then
            catalogContent=`cat $catalog | awk -F 'key":' '{print $2}'|sed 's/^"\(.*\)".*/\1/'`
            echo "Here is the damn key ..whoah .. $catalogContent for $selectedenv"
            echo ":::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
            deploy-console "$catalogContent" "deploy" "$4" "$5" "$6"
          else
            echo "No Catalog file exist here $catalog for $selectedenv"
          fi
        else
          echo "Do Nothing as there is no new commit or no history at this dir  for this env $selectedenv"
        fi

      else  
        echo "Thie environment manifest does not exist:: $selectedenv"
      fi
done
unset IFS
exit 0

