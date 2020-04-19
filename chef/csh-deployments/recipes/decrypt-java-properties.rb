

def load_properties(properties_filename)
    properties = {}
    File.open(properties_filename, 'r') do |properties_file|
      properties_file.read.each_line do |line|
        line.strip!

        if (line.length > 0 and line[0] != ?# and line[0] != ?=)
          puts "Selected:: ------ #{line}"

          i = line.index('=')
          if (i)
            puts "Index  equal found"
            properties[line[0..i - 1].strip] = line[i + 1..-1].strip
          else
            properties[line] = ''
          end
        end
      end
    end
    properties
end



puts "Running Decrypt Utility for OSB Property"
Chef::Log.info("Start decrypt execution ")

target_asset_path = node["target_asset"]
Chef::Log.info("The property Location  #{target_asset_path} ")


puts "Load Java Properties Files  ..here ... "
deployment_properties = load_properties(target_asset_path)

puts "Here is the OSB Property Hash : #{deployment_properties}"
puts "The data type is #{deployment_properties.class}"



target_file_path =target_asset_path.gsub(".properties","-updated.properties")

puts "The target file path ::  #{target_file_path}"
decrypt_property_file = File.open(target_file_path, 'w')

deployment_properties.each do |key,value|
    if (value.start_with?("{AES}","{AES2}"))
        decrypt_property_file.puts "#{key}=#{Mint::AesEncryption.decrypt(value)}\n"
    else
        decrypt_property_file.puts "#{key}=#{value}\n"
    end
end
decrypt_property_file.close

puts "Completed decrypt property generation"

Chef::Log.info("Completed execution ")
