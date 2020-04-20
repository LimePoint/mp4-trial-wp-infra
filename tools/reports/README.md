How to Generate Reports

Execute the following steps on your laptop (MAC) in order to generate HTML report for newly built environment:

# Pre-reqs

## Install Node.js (Once)

Node.js is required to get npm tool. You can download from https://nodejs.org/en/. Latest is fine.

##Install the HomeBrew

## Install 'jq' (https://stedolan.github.io/jq/) [Once]
jq is a lightweight and flexible command-line JSON processor.  jq is like sed for JSON data - you can use it to slice and filter and map and transform structured data with the same ease that sed, awk, grep. 
To install jq, you need to install HomeBrew (MAC) first. 

brew install jq (for MAC)

# Install NPM
brew install npm (for MAC)

## Install json2xml-cli (once)
npm install -g json2xml-cli

# Useful reports

## Environment URLs
Set the following variables

export OBP_REPO_HOME=/Users/romil/cohesion_repos/westpac_mp-001_techstack
export OBP_REPORTS_HOME=${OBP_REPO_HOME}/tools/reports
export OBP_ENV_NAME=dev2

Run the follow command:

json2xml -i ${OBP_REPO_HOME}/chef/data_bags/environment_vars/${OBP_ENV_NAME}_vars.json -o /tmp/out.xml && echo '<config>' > /tmp/out_updated.xml && cat /tmp/out.xml >> /tmp/out_updated.xml && echo '</config>' >> /tmp/out_updated.xml && java -jar ${OBP_REPORTS_HOME}/saxon9he.jar /tmp/out_updated.xml ${OBP_REPORTS_HOME}/databag.xslt > ${OBP_REPORTS_HOME}/${OBP_ENV_NAME}_env_details.html


##	How to create Wiki page?
Push the HTML report into LP's GIT repo then sync to WP's GIT repo. Create a Wiki page https://confluence.srv.westpac.com.au/display/CSH/Environments+for+Release+1.01/<ENV-NAME>, click Edit and select <ENV>_env_details.html text and paste to to wiki page.


