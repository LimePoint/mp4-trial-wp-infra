How to Export Import Deployment Plans

curl -u username:password https://mintpress-rtd-csh.srv.westpac.com.au/cshtest/rest/envmint/1.0/exportProject?project=TST4DEPLOYMENTS2018JAN180900 -o /tmp/tst4_deployments.json

curl -u username:password https://mintpress-rtd-csh.srv.westpac.com.au/cshtest/rest/envmint/1.0/importProject --data @dev1_deployments.json --header "Content-Type: application/json"