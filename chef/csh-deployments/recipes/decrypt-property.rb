
puts "Running Decrypt Utility"
Chef::Log.info("Start decrypt execution ")

target_asset_path = node["target_asset"]
Chef::Log.info("The property Location  #{target_asset_path} ")

config_properties= File.read(target_asset_path)
config_vars = JSON.parse(config_properties)
puts config_vars
deployment_properties =  config_vars["/getDeploymentProperties.json?environment=LOCAL"]

puts "Here are the target vars : #{deployment_properties}"
puts "The date type is #{deployment_properties.class}"

deployment_properties.each_with_index do | item, index |

    #puts "Item #{item} and index #{index}"
    #puts deployment_properties[index]
    #puts deployment_properties[index]["name"]
    #puts deployment_properties[index]["value"]

   if (deployment_properties[index]["value"].start_with?("{AES}","{AES2}"))
      puts "This  is a encrypted password string ===> #{item}"
      deployment_properties[index]["value"] = Mint::AesEncryption.decrypt(deployment_properties[index]["value"])
    end

end

puts "<start_decrypt>#{config_vars.to_json}<end_decrypt> "
Chef::Log.info("Completed execution ")
