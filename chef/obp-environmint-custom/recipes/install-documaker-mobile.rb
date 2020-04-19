require 'tempfile'
require 'base64'

# make our utils usable from Recipe, and from RubyBlock and within Template
Chef::Recipe.send(:include, OBPOrchestration::Utils)
Chef::Resource::RubyBlock.send(:include, OBPOrchestration::Utils)
Chef::Resource::Template.send(:include, OBPOrchestration::Utils)

install_dir='/oracle/app/binaries/obpdoc/fmw/odee_12/documaker'
mobile_dir='/oracle/app/binaries/obpdoc/fmw/odee_12/documaker/mstrres/mobile'
install_file='/oracle/stage/documaker/12.6.0/mobile/ODM12.6.00.32242Linuxx86.sh'
tmp_dir='/oracle/app/binaries/obpdoc/tmp'

bash 'Install Documaker Mobile' do
	code <<-EOH
    if [ ! -x #{install_file} ]; then
    	echo 'Cannot execute #{install_file}, Check if permissions are proper'
    	exit 1
    fi
    mkdir -p "#{tmp_dir}"
    echo 'InstallationDir=#{install_dir}' > "#{tmp_dir}/mob.props"
    echo 'sys.languageId=en' >> "#{tmp_dir}/mob.props"
    #{install_file} -q -varfile #{tmp_dir}/mob.props
	EOH
	user 'oracle'
	group 'oinstall'
	not_if { File.exist?("#{mobile_dir}") }
end
