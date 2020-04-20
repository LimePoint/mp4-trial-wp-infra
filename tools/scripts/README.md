** How to generate environment data bag file for OCloud **
1. Update the ocloud-environment-generation-template.json with the correct environment name
2. Run the following command:
ruby erb_harness.rb ../../chef/obp-environmint-custom/templates/default/opcdev_vars.json.erb ocloud-environment-generation-template.json > full_path_ofenv_name_vars.json
e.g
ruby erb_harness.rb ../../chef/obp-environmint-custom/templates/default/opcdev_vars.json.erb ocloud-environment-generation-template.json > ../../chef/obp-environmint-custom/files/data_bags/bpd10_vars.json
