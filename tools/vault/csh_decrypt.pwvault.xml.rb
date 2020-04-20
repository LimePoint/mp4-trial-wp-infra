#require_relative "../../../../../home/mintpress/bin/mint_aes_encryption"
require 'json'
require 'environmint-common'

pw=JSON.parse(File.read(ARGV[0]))
env=pw['id']

puts '<?xml version="1.0" encoding="utf-8" standalone="yes"?>'
puts '<pwlist>'

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
					puts '<pwentry>'
					puts "<group tree=\"#{env}\">#{k}</group>"
					puts "<title>#{title}</title>"
					puts "<username>#{user}</username>"
	  				puts "<password>#{pass}</password>"
					puts '</pwentry>'
				end
			end
        end
	end
end
puts '</pwlist>'

