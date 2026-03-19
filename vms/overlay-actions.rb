def overlay_actions (all_hosts, a_dns_entries, cname_dns_entries)
  # Building blocks
  OpsChain.properties.assets.each do |asset_name, deets|
    matcher = asset_name.sub("obp", "obp.*")

    configs = {
        "hosts_std" => [%w(create start stop restart exists? destroy unbootstrap), all_hosts, ":"],
        "hosts_bs"  => [%w(bootstrap update-security-rules), all_hosts, "-"],
        "a-dns"     => [%w(create exists? remove valid? wait_for_valid), a_dns_entries, ":"],
        "cname-dns" => [%w(create exists? remove valid? wait_for_valid), cname_dns_entries, ":"]
    }

    configs.each do |key, (actions, source, sep)|
      suffix = key.split('_').first
      actions.each do |act|
        # 1. Asset-level action
        # obpcid-hosts-create, obpcid-a-dns-create obpcid-cname-dns-create
        a_id = "#{asset_name}-#{suffix}-#{act}"
        a_steps = source.filter_map { |h| "#{h}#{sep}#{act}" if h.match?(/#{matcher}/) }
        action a_id, steps: a_steps, run_as: :parallel, description: a_id

        # 2. Host-level actions
        deets.hosts.each do |host|
          # obpcbpd21cid01-vm-create obpcbpd21cid01-vm-a-dns-create obpcbpd21cid01-vm-cname-dns-create
          if suffix.include?("dns")
            h_id = "#{host.name}-vm-#{suffix}-#{act}"
          else
            h_id = "#{host.name}-vm-#{act}"
          end
          h_steps = source.filter_map { |h| "#{h}#{sep}#{act}" if h.match?(/#{host.name}/) }
          action h_id, steps: h_steps, run_as: :parallel, description: h_id

        end
      end
    end
  end

  # Assembly
  OpsChain.properties.assets.each do | asset_name, deets |

    %w(create).each do |act|
      # action "#{asset_name}-dns-#{act}",  steps: ["#{asset_name}-a-dns-#{act}", "#{asset_name}-cname-dns-#{act}"], run_as: :parallel, description: "#{asset_name}-dns-#{act}"
      action "#{asset_name}-dns-#{act}",  steps: ["#{asset_name}-a-dns-#{act}", "#{asset_name}-cname-dns-#{act}"], run_as: :sequential, description: "#{asset_name}-dns-#{act}"
      action "#{asset_name}-infra-#{act}", steps: [ "#{asset_name}-hosts-#{act}", "#{asset_name}-dns-#{act}"], run_as: :sequential, description: "#{asset_name}-infra-create"
      action "#{asset_name}-infra-#{act}-and-bootstrap", steps: [ "#{asset_name}-infra-#{act}", "#{asset_name}-hosts-bootstrap", "#{asset_name}-hosts-update-security-rules"], run_as: :sequential, description: "#{asset_name}-infra-create-and-bootstrap"
    end

    %w(destroy).each do |act|
      action "#{asset_name}-#{act}",steps: [ "#{asset_name}-hosts-unbootstrap", "#{asset_name}-hosts-#{act}" ], run_as: :sequential, description: "#{asset_name}-#{act}"
    end

    %w(start stop restart exists?).each do |act|
      action "#{asset_name}-#{act}", steps: ["#{asset_name}-hosts-#{act}"], run_as: :parallel, description: "#{asset_name}-#{act}"
    end

    deets.hosts.each do |host|
      %w(create).each do |act|
        # action "#{host.name}-dns-#{act}", steps: ["#{host.name}-vm-a-dns-#{act}", "#{host.name}-vm-cname-dns-#{act}"], description: "#{host.name}-dns-#{act}", run_as: :parallel
        action "#{host.name}-dns-#{act}", steps: ["#{host.name}-vm-a-dns-#{act}", "#{host.name}-vm-cname-dns-#{act}"], description: "#{host.name}-dns-#{act}", run_as: :sequentia
        action "#{host.name}-infra-#{act}", steps: [ "#{host.name}-vm-#{act}", "#{host.name}-dns-#{act}" ], description: "#{host.name}-infra-#{act}", run_as: :sequential
        action "#{host.name}-infra-#{act}-and-bootstrap", steps: [ "#{host.name}-infra-#{act}", "#{host.name}-vm-bootstrap", "#{host.name}-vm-update-security-rules" ] , description: "#{host.name}-infra-#{act}-and-bootstrap", run_as: :sequential

      end

      %w(destroy).each do |act|
        action "#{host.name}-#{act}", steps: ["#{host.name}-vm-unbootstrap", "#{host.name}-vm-#{act}"], description: "#{host.name}-#{act}", run_as: :sequential
      end

      %w(start stop restart exists?).each do |act|
        action "#{host.name}-#{act}", steps: [ "#{host.name}-vm-#{act}" ], description: "#{host.name}-vm-#{act}"
      end
    end
  end
end