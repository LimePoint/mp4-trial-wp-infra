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

				proceed=true

				case
				when user.match(/^weblogic/)
					title="Weblogic Admin Credentials"
				when user.match(/INSTALL_DBA/)
					title="Database SYS Credentials"
					proceed=false
				when user.match(/^keystorepass/)
					title="KeyStore Credentials"
				when user.match(/^truststorepass/)
					title="TrustStore Credentials"
				when user.match(/-MDS/), user.match(/-SOAINFRA/), user.match(/_ODI/)
					title="RCU Schema Password"
				else
					title="#{user}"
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

