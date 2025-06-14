# frozen_string_literal: true

require 'opschain'
require 'mintpress-infrastructure-oci'

resource_type :infrastructure_oci_oci_platform do
  controller MintPress::InfrastructureOci::OciPlatform
end

resource_type :infrastructure_chef_bootstrapper do
  controller MintPress::Infrastructure::ChefBootstrapper
end

resource_type :infrastructure_oci_oci_dns_zone do
  controller MintPress::InfrastructureOci::OCIDnsZone
end

resource_type :infrastructure_oci_oci_dns_entry do
  controller MintPress::InfrastructureOci::OCIDnsEntry
end

resource_type :infrastructure_oci_oci_host do
  controller MintPress::InfrastructureOci::OCIHost
end

resource_type :infrastructure_oci_oci_storage do
  controller MintPress::InfrastructureOci::OCIStorage
end

resource_type :infrastructure_oci_vcn do
  controller MintPress::InfrastructureOci::VCN
end

resource_type :infrastructure_oci_subnet do
  controller MintPress::InfrastructureOci::Subnet
end

resource_type :infrastructure_oci_route_table do
  controller MintPress::InfrastructureOci::RouteTable
end

resource_type :infrastructure_oci_dhcp do
  controller MintPress::InfrastructureOci::Dhcp
end

resource_type :infrastructure_oci_internet_gateway do
  controller MintPress::InfrastructureOci::InternetGateway
end

resource_type :infrastructure_oci_nat_gateway do
  controller MintPress::InfrastructureOci::NatGateway
end

resource_type :infrastructure_oci_service_gateway do
  controller MintPress::InfrastructureOci::ServiceGateway
end

resource_type :infrastructure_oci_route_rule do
  controller MintPress::InfrastructureOci::RouteRule
end

resource_type :infrastructure_oci_security_list do
  controller MintPress::InfrastructureOci::SecurityList
end

resource_type :infrastructure_oci_network_security_group do
  controller MintPress::InfrastructureOci::NetworkSecurityGroup
end

resource_type :infrastructure_oci_oci_shared_storage do
  controllerMintPress::InfrastructureOci::OCISharedStorage
end






