#require_relative "../../../../../home/mintpress/bin/mint_aes_encryption"
require 'json'
require 'environmint-common'

pw=JSON.parse(File.read(ARGV[0]))
env=pw['id']

puts '<html><body><table>'

pw.each do |k,v|
	if k.match(/^obp/)

        if v.is_a?(Hash)
			v.each do |user,pass|
				pass=Mint::AesEncryption.decrypt(pass)
				proceed=false
				case
				when user.match(/^wlsmonitor/)
					title="Weblogic Monitor Credentials"
          proceed=true
				when user.match(/^obpreadonly/)
					title="OBPHost Database Read Only Credentials"
          proceed=true
				when user.match(/readonly/)
					title="LDAP Read Only Credentials"
          proceed=true
				end

				if proceed
					puts '<tr>'
					puts "<td>#{k}</td>"
					puts "<td>#{title}</td>"
					puts "<td>#{user}</td>"
	  				puts "<td>#{pass}</td>"
					puts '</tr>'
				end
			end
        end
	end
end
puts '</table></body></html>'

