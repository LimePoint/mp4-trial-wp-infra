#!/bin/bash
HELP_STR="Usage: $0 <Limepoint-Cont-Delivery-Home> <List of Environments> <Orchestration Home> <Console User> <Console Pwd> <Console URL> <Console Status URL>"
deploy-console() {
  echo "The Orchestration Key ::$1 "
  echo "The Action      :: $2"
  echo "Console User    :: $3"
  echo "Console Pwd     :: $4"
  echo "Console API Url :: $5"
  echo " <<<<DEPLOY>>>> "
  json_for_post="{\"uuid\": \"$1\", \"actionCode\": \"$2\", \"itemCode\": \"OBPCOMP\" }"
  response=`curl --write-out %{http_code} --user "$3:$4" "$5" -d "$json_for_post" -H "Content-Type: application/json"`
  echo "Reponse from the Request $response"
  return 0
}


check-console() {
  echo "The Orchestration Key ::$1 "
  echo "Console User    :: $2"
  echo "Console Pwd     :: $3"
  echo "Console status API Url :: $4"
  echo " <<<<STATUS>>>> "
  echo "Here is the url $4?uuid=$1"
  response=`curl --write-out %{http_code} --user "$2:$3" "$4?uuid=$1"  -H "Content-Type: application/json"`
  echo "Reponse from the Request $response"
  invocationContent=`echo $response | awk -F 'currentActionInvocation":' '{print $2}'|sed 's/}.*$//g'`
  if [ "$invocationContent" = "null" ]
  then
      echo "Yes it is null, good to invoke"
      return 1
  else
      echo "No the instance is busy"
      return 0
  fi
  echo "The Catalog instance status check response is::  $invocationContent"
  return 0
}


[ "$1" = "" ] && echo "Expecting <Limepoint-Cont-Delivery-Home> ::  $HELP_STR" && exit 1
[ "$2" = "" ] && echo "Expecting <List of Environments> :: $HELP_STR" && exit 1
[ "$3" = "" ] && echo "Expecting <Orchestration Home> :: $HELP_STR" && exit 1
[ "$4" = "" ] && echo "Expecting <Console User> :: $HELP_STR" && exit 1
[ "$5" = "" ] && echo "Expecting <Console Pwd> :: $HELP_STR" && exit 1
[ "$6" = "" ] && echo "Expecting <Console URL> :: $HELP_STR" && exit 1
[ "$7" = "" ] && echo "Expecting <Console Status URL> :: $HELP_STR" && exit 1
echo "Continous Delivery Home: $1"
echo "Environment List : $2"
echo "Orchestration Key Home : $3"
echo "Console User : $4"
echo "Console PWD : $5"
echo "Console URL : $6"
echo "Console Status URL : $7"
CD_HOME=$1
list=${2^^}
ORCH_KEY_HOME=$3

IFS=', ' read -r -a array <<< "$list"
echo "Executing from this directory :: Must be under Git Manifest Repo"; pwd
echo "Listing from this directory ::"; ls -la

for selectedenv in $(dirname `ls */manifest.json`); do
  echo "Okay ... lets start probing this env $selectedenv"
  echo "================================================="
  currentContent="$(git log -n 1  ./$selectedenv/manifest.json|awk 'FNR == 1 {print $2}')"
  echo "Current Content => $currentContent"
  previousContent=`cat $CD_HOME/$selectedenv-manifest-last-commit.log`
  echo "Previous Content => $previousContent"
  if [ "$previousContent" != ""  -a  "$currentContent" != "$previousContent" ]; then
    echo "Updating new commits"
    echo $currentContent > $CD_HOME/$selectedenv-manifest-last-commit.log
    echo "Checking if $selectedenv is an AUTO-DEPLOY environment"
    for env in "${array[@]}"; do
      if [ $env == $selectedenv ]; then
        echo "$selectedenv is an AUTO-DEPLOY environment. Let's Deploy!!"
        catalog="$ORCH_KEY_HOME/obpcomp.${selectedenv,,}"".json"
        if [ -e "$catalog" ]; then
          catalogContent=`cat $catalog | awk -F 'key":' '{print $2}'|sed 's/^"\(.*\)".*/\1/'`
          echo "Here is the damn key ..whoah .. $catalogContent for $selectedenv"
          echo "Now check the status of the console"
          check-console "$catalogContent" "$4" "$5" "$7"
          console_status=$?
          echo "The console status for the env $selectedenv is  $console_status"
          if [ $console_status -eq 1 ]; then
            echo "The console status for the env $selectedenv is  $console_status"
            echo ":::::::::::::::::::::::::::::::::: INVOKE DEPLOY ::::::::::::::::::::::::::::::::::"
            deploy-console "$catalogContent" "deploy" "$4" "$5" "$6"
          else
            echo "The console status for the env $selectedenv is  $console_status - Environment is busy with a deploy or upload action"
          fi
        else
          echo "No Catalog file exist here $catalog for $selectedenv"
        fi
        break
      fi
    done
  elif [ -z "$previousContent" ]; then
    echo "This is a brand new env , set the current commit hash to the file"
    echo $currentContent > $CD_HOME/$selectedenv-manifest-last-commit.log
  else
    echo "Do Nothing as there is no new commit found here for $selectedenv"
  fi
done
unset IFS
exit 0