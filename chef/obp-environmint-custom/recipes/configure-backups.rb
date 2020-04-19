#
# Cookbook  :: obp-environment-custom
# Recipe    :: configure-backups
#

assetlist = %w[ soa obh obu osb odi doc ipm urm oim cim oid cid oam osb bip ]
nodelist=[]
search(:node, "chef_environment:#{node.chef_environment}").each { |n| nodelist << n['hostname'].split('.')[0] if n['hostname'].split( )[0].match?(/.*(\d{2}|db)/) }
puts "Backups will be configured for "+nodelist.inspect
dirlist = nodelist.map {|n| "/backups/#{n} /backups/logs/#{n}".split(' ')}

directory '/root/backup_scripts' do
    owner 'root'
    group 'root'
    mode '0700'
    recursive true
end

%w[ /backups /backups/logs ].each do |path|
    directory path do
        owner 'oracle'
        group 'oinstall'
        mode '0755'
        recursive true
    end
end

dirlist.each do |dirs|
    dirs.each do |d|
        puts "creating '#{d}'"
        directory d do
            owner 'oracle'
            group 'oinstall'
            mode '0755'
            recursive true
            action :create
        end
    end
end

nodelist.each do |n|
    asset_code = "obp" + n.match(Regexp.union(assetlist)).to_s
    lv_minute = n.match?(Regexp.union(%w[osb odi bip oam soa obh obu])) ? 30 : 00
    lv_hour = n.match?(Regexp.union(%w[soa obh obu ipm doc db])) ? 2 : 3
    puts "Backup starts at #{lv_hour}:#{lv_minute} for #{n}"
    case
    when n.end_with?('db')
        puts "Backup DB"
        template "Setup-Rsync-Script-for-DB-backups" do
            source 'backup_scripts/rsync-db.sh.erb'
            path '/root/backup_scripts/rsync-db.sh'
            owner 'root'
            group 'root'
            mode '0700'
            variables(
                :targetvm => n,
                :asset => asset_code
            )
        end
        cron_d "Setup-cron-job-for-DB-backups" do
            cron_name "backup-obpdb"
            minute lv_minute
            hour lv_hour
            command '/root/backup_scripts/rsync-db.sh'
            user 'root'
        end
    when n.match?(Regexp.union(assetlist))
        puts "Backup #{asset_code}"
        template "Setup-Rsync-Script-for-#{asset_code}-backups" do
            source 'backup_scripts/rsync-fmw.sh.erb'
            path "/root/backup_scripts/rsync-#{asset_code}.sh"
            owner 'root'
            group 'root'
            mode '0700'
            variables(
                :targetvm => n,
                :asset => asset_code
            )
        end
        cron_d "Setup-cron-job-for-#{asset_code}-backups" do
            cron_name "backup-#{asset_code}"
            minute lv_minute
            hour lv_hour
            command "/root/backup_scripts/rsync-#{asset_code}.sh"
            user 'root'
        end
    end
end
