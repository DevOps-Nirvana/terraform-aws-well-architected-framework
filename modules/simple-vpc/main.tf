terraform {
  required_version = ">= 0.12"
}

# Variables for the typical user to set
variable "cidr" {
  description = "The CIDR block for the VPC. Default value is a valid CIDR, but not acceptable by AWS and should be overridden.  Note: This should be a /16 for this module to work properly."
  type        = string
  # default     = "10.0.0.0/16"
}
variable "is_highly_available" {
  description = "Sets logic if this should be highly available (aka, for production).  This will cost more money (eg: create nat gateway per AZ)"
  type        = bool
  default     = true
}

# This is our input (instead of asking the user) to get the AZ's available in this region
data "aws_availability_zones" "azs" {}

# These are the "magic" of this ezvpc module, specifying the azs and subnetting automatically
locals {
  # Figure out our number of AZs, if the user set it or if we automatically use best practice
  number_of_azs = (var.number_of_azs > 0 ? var.number_of_azs : (var.is_highly_available == true ? 3 : 2))
  # Get an array of the named AZs, unless the user overrides it
  azs = (length(var.azs) > 0 ? var.azs : slice(sort(data.aws_availability_zones.azs.names), 0, local.number_of_azs))
  # Generate the private subnetting automatically
  private_subnets = (length(var.private_subnets) > 0 ? var.private_subnets :
                      [for num in var.number_of_azs_subnet_numbers[local.number_of_azs]:
                        cidrsubnet(var.cidr, lookup(var.cidr_addition_map, local.number_of_azs), num)
                      ]
                    )
  # Generate the public subnetting automatically
  public_subnets  = (length(var.public_subnets) > 0 ? var.public_subnets :
                      [for num in var.number_of_azs_subnet_numbers[local.number_of_azs]:
                        cidrsubnet(var.cidr, lookup(var.cidr_addition_map, local.number_of_azs), num + local.number_of_azs)
                      ]
                    )
  # Custom logic for nat based on is_highly_available
  single_nat_gateway = (var.single_nat_gateway != null ? var.single_nat_gateway :
                          (var.is_highly_available == true ? false : true)
                        )
  one_nat_gateway_per_az = (var.one_nat_gateway_per_az != null ? var.one_nat_gateway_per_az :
                              (var.is_highly_available == true ? true: false)
                            )
}

# These are variables that help us function and do CIDR math, DO NOT EDIT unless you know what you're doing
# TODO: This seems wholly unnecessary but I could not find a better way to do this with the inline-for loop
#       above in locals.private_subnets and locals.public_subnets
variable "number_of_azs_subnet_numbers" {
  default = {
    "1" = [0]
    "2" = [0,1]
    "3" = [0,1,2]
    "4" = [0,1,2,3]
  }
}
# These are pre-calculated values to maximize usage of a /16 CIDR range assuming one public and one private subnet
variable "cidr_addition_map" {
  description = "lookup map for cidr additions for automatic subnetting"
  default = {
    "1" = "1"
    "2" = "2"
    "3" = "3"
    "4" = "3"
  }
}
# This allows you to force-set the number of AZs, this is incase you only want 2 AZ's or maybe even 4 AZs on a production infra
variable "number_of_azs" {
  description = "Override the number of AZs to span, this should be 1, 2, 3 or 4.  Optional, if not specified it will use intelligent value based on is_highly_available (2 for no, 3 for yes)"
  type        = number
  default     = 0
}
# This allows you to force the list of AZs used.  This is useful if you want to ensure you're using the same list of AZs as some previous infra
variable "azs" {
  description = "OPTIONAL - A list of availability zones names or ids in the region, only set this if you want to force certain AZs, with ezvpc this is automatic"
  type        = list(string)
  default     = []
}

output "number_of_azs" {
  description = "number_of_azs"
  value       = local.number_of_azs
}

# Here's our VPC module as a submodule initialized with automatic AZ and CIDR subnetting
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"  # Latest as of July 9, 2023

  # These are the few that we're overriding the logic for this module
  azs = local.azs
  public_subnets = local.public_subnets
  private_subnets = local.private_subnets
  single_nat_gateway = local.single_nat_gateway
  one_nat_gateway_per_az = local.one_nat_gateway_per_az

  # Pass-through basically all the rest of the input variables
  create_vpc = var.create_vpc
  name = var.name
  cidr = var.cidr
  secondary_cidr_blocks = var.secondary_cidr_blocks
  instance_tenancy = var.instance_tenancy
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support = var.enable_dns_support
  enable_network_address_usage_metrics = var.enable_network_address_usage_metrics
  use_ipam_pool = var.use_ipam_pool
  ipv4_ipam_pool_id = var.ipv4_ipam_pool_id
  ipv4_netmask_length = var.ipv4_netmask_length
  enable_ipv6 = var.enable_ipv6
  ipv6_cidr = var.ipv6_cidr
  ipv6_ipam_pool_id = var.ipv6_ipam_pool_id
  ipv6_netmask_length = var.ipv6_netmask_length
  ipv6_cidr_block_network_border_group = var.ipv6_cidr_block_network_border_group
  vpc_tags = var.vpc_tags
  tags = var.tags
  enable_dhcp_options = var.enable_dhcp_options
  dhcp_options_domain_name = var.dhcp_options_domain_name
  dhcp_options_domain_name_servers = var.dhcp_options_domain_name_servers
  dhcp_options_ntp_servers = var.dhcp_options_ntp_servers
  dhcp_options_netbios_name_servers = var.dhcp_options_netbios_name_servers
  dhcp_options_netbios_node_type = var.dhcp_options_netbios_node_type
  dhcp_options_tags = var.dhcp_options_tags
  public_subnet_assign_ipv6_address_on_creation = var.public_subnet_assign_ipv6_address_on_creation
  public_subnet_enable_dns64 = var.public_subnet_enable_dns64
  public_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.public_subnet_enable_resource_name_dns_aaaa_record_on_launch
  public_subnet_enable_resource_name_dns_a_record_on_launch = var.public_subnet_enable_resource_name_dns_a_record_on_launch
  public_subnet_ipv6_prefixes = var.public_subnet_ipv6_prefixes
  public_subnet_ipv6_native = var.public_subnet_ipv6_native
  map_public_ip_on_launch = var.map_public_ip_on_launch
  public_subnet_private_dns_hostname_type_on_launch = var.public_subnet_private_dns_hostname_type_on_launch
  public_subnet_names = var.public_subnet_names
  public_subnet_suffix = var.public_subnet_suffix
  public_subnet_tags = var.public_subnet_tags
  public_subnet_tags_per_az = var.public_subnet_tags_per_az
  public_route_table_tags = var.public_route_table_tags
  public_dedicated_network_acl = var.public_dedicated_network_acl
  public_inbound_acl_rules = var.public_inbound_acl_rules
  public_outbound_acl_rules = var.public_outbound_acl_rules
  public_acl_tags = var.public_acl_tags
  private_subnet_assign_ipv6_address_on_creation = var.private_subnet_assign_ipv6_address_on_creation
  private_subnet_enable_dns64 = var.private_subnet_enable_dns64
  private_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.private_subnet_enable_resource_name_dns_aaaa_record_on_launch
  private_subnet_enable_resource_name_dns_a_record_on_launch = var.private_subnet_enable_resource_name_dns_a_record_on_launch
  private_subnet_ipv6_prefixes = var.private_subnet_ipv6_prefixes
  private_subnet_ipv6_native = var.private_subnet_ipv6_native
  private_subnet_private_dns_hostname_type_on_launch = var.private_subnet_private_dns_hostname_type_on_launch
  private_subnet_names = var.private_subnet_names
  private_subnet_suffix = var.private_subnet_suffix
  private_subnet_tags = var.private_subnet_tags
  private_subnet_tags_per_az = var.private_subnet_tags_per_az
  private_route_table_tags = var.private_route_table_tags
  private_dedicated_network_acl = var.private_dedicated_network_acl
  private_inbound_acl_rules = var.private_inbound_acl_rules
  private_outbound_acl_rules = var.private_outbound_acl_rules
  private_acl_tags = var.private_acl_tags
  database_subnets = var.database_subnets
  database_subnet_assign_ipv6_address_on_creation = var.database_subnet_assign_ipv6_address_on_creation
  database_subnet_enable_dns64 = var.database_subnet_enable_dns64
  database_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.database_subnet_enable_resource_name_dns_aaaa_record_on_launch
  database_subnet_enable_resource_name_dns_a_record_on_launch = var.database_subnet_enable_resource_name_dns_a_record_on_launch
  database_subnet_ipv6_prefixes = var.database_subnet_ipv6_prefixes
  database_subnet_ipv6_native = var.database_subnet_ipv6_native
  database_subnet_private_dns_hostname_type_on_launch = var.database_subnet_private_dns_hostname_type_on_launch
  database_subnet_names = var.database_subnet_names
  database_subnet_suffix = var.database_subnet_suffix
  create_database_subnet_route_table = var.create_database_subnet_route_table
  create_database_internet_gateway_route = var.create_database_internet_gateway_route
  create_database_nat_gateway_route = var.create_database_nat_gateway_route
  database_route_table_tags = var.database_route_table_tags
  database_subnet_tags = var.database_subnet_tags
  create_database_subnet_group = var.create_database_subnet_group
  database_subnet_group_name = var.database_subnet_group_name
  database_subnet_group_tags = var.database_subnet_group_tags
  database_dedicated_network_acl = var.database_dedicated_network_acl
  database_inbound_acl_rules = var.database_inbound_acl_rules
  database_outbound_acl_rules = var.database_outbound_acl_rules
  database_acl_tags = var.database_acl_tags
  redshift_subnets = var.redshift_subnets
  redshift_subnet_assign_ipv6_address_on_creation = var.redshift_subnet_assign_ipv6_address_on_creation
  redshift_subnet_enable_dns64 = var.redshift_subnet_enable_dns64
  redshift_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.redshift_subnet_enable_resource_name_dns_aaaa_record_on_launch
  redshift_subnet_enable_resource_name_dns_a_record_on_launch = var.redshift_subnet_enable_resource_name_dns_a_record_on_launch
  redshift_subnet_ipv6_prefixes = var.redshift_subnet_ipv6_prefixes
  redshift_subnet_ipv6_native = var.redshift_subnet_ipv6_native
  redshift_subnet_private_dns_hostname_type_on_launch = var.redshift_subnet_private_dns_hostname_type_on_launch
  redshift_subnet_names = var.redshift_subnet_names
  redshift_subnet_suffix = var.redshift_subnet_suffix
  enable_public_redshift = var.enable_public_redshift
  create_redshift_subnet_route_table = var.create_redshift_subnet_route_table
  redshift_route_table_tags = var.redshift_route_table_tags
  redshift_subnet_tags = var.redshift_subnet_tags
  create_redshift_subnet_group = var.create_redshift_subnet_group
  redshift_subnet_group_name = var.redshift_subnet_group_name
  redshift_subnet_group_tags = var.redshift_subnet_group_tags
  redshift_dedicated_network_acl = var.redshift_dedicated_network_acl
  redshift_inbound_acl_rules = var.redshift_inbound_acl_rules
  redshift_outbound_acl_rules = var.redshift_outbound_acl_rules
  redshift_acl_tags = var.redshift_acl_tags
  elasticache_subnets = var.elasticache_subnets
  elasticache_subnet_assign_ipv6_address_on_creation = var.elasticache_subnet_assign_ipv6_address_on_creation
  elasticache_subnet_enable_dns64 = var.elasticache_subnet_enable_dns64
  elasticache_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.elasticache_subnet_enable_resource_name_dns_aaaa_record_on_launch
  elasticache_subnet_enable_resource_name_dns_a_record_on_launch = var.elasticache_subnet_enable_resource_name_dns_a_record_on_launch
  elasticache_subnet_ipv6_prefixes = var.elasticache_subnet_ipv6_prefixes
  elasticache_subnet_ipv6_native = var.elasticache_subnet_ipv6_native
  elasticache_subnet_private_dns_hostname_type_on_launch= var.elasticache_subnet_private_dns_hostname_type_on_launch
  elasticache_subnet_names = var.elasticache_subnet_names
  elasticache_subnet_suffix = var.elasticache_subnet_suffix
  elasticache_subnet_tags = var.elasticache_subnet_tags
  create_elasticache_subnet_route_table = var.create_elasticache_subnet_route_table
  elasticache_route_table_tags = var.elasticache_route_table_tags
  create_elasticache_subnet_group = var.create_elasticache_subnet_group
  elasticache_subnet_group_name = var.elasticache_subnet_group_name
  elasticache_subnet_group_tags = var.elasticache_subnet_group_tags
  elasticache_dedicated_network_acl = var.elasticache_dedicated_network_acl
  elasticache_inbound_acl_rules = var.elasticache_inbound_acl_rules
  elasticache_outbound_acl_rules = var.elasticache_outbound_acl_rules
  elasticache_acl_tags = var.elasticache_acl_tags
  intra_subnets = var.intra_subnets
  intra_subnet_assign_ipv6_address_on_creation = var.intra_subnet_assign_ipv6_address_on_creation
  intra_subnet_enable_dns64 = var.intra_subnet_enable_dns64
  intra_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.intra_subnet_enable_resource_name_dns_aaaa_record_on_launch
  intra_subnet_enable_resource_name_dns_a_record_on_launch = var.intra_subnet_enable_resource_name_dns_a_record_on_launch
  intra_subnet_ipv6_prefixes = var.intra_subnet_ipv6_prefixes
  intra_subnet_ipv6_native = var.intra_subnet_ipv6_native
  intra_subnet_private_dns_hostname_type_on_launch = var.intra_subnet_private_dns_hostname_type_on_launch
  intra_subnet_names = var.intra_subnet_names
  intra_subnet_suffix = var.intra_subnet_suffix
  intra_subnet_tags = var.intra_subnet_tags
  intra_route_table_tags = var.intra_route_table_tags
  intra_dedicated_network_acl = var.intra_dedicated_network_acl
  intra_inbound_acl_rules = var.intra_inbound_acl_rules
  intra_outbound_acl_rules = var.intra_outbound_acl_rules
  intra_acl_tags = var.intra_acl_tags
  outpost_subnets = var.outpost_subnets
  outpost_subnet_assign_ipv6_address_on_creation = var.outpost_subnet_assign_ipv6_address_on_creation
  outpost_az = var.outpost_az
  customer_owned_ipv4_pool = var.customer_owned_ipv4_pool
  outpost_subnet_enable_dns64 = var.outpost_subnet_enable_dns64
  outpost_subnet_enable_resource_name_dns_aaaa_record_on_launch = var.outpost_subnet_enable_resource_name_dns_aaaa_record_on_launch
  outpost_subnet_enable_resource_name_dns_a_record_on_launch = var.outpost_subnet_enable_resource_name_dns_a_record_on_launch
  outpost_subnet_ipv6_prefixes = var.outpost_subnet_ipv6_prefixes
  outpost_subnet_ipv6_native = var.outpost_subnet_ipv6_native
  map_customer_owned_ip_on_launch = var.map_customer_owned_ip_on_launch
  outpost_arn = var.outpost_arn
  outpost_subnet_private_dns_hostname_type_on_launch = var.outpost_subnet_private_dns_hostname_type_on_launch
  outpost_subnet_names = var.outpost_subnet_names
  outpost_subnet_suffix = var.outpost_subnet_suffix
  outpost_subnet_tags = var.outpost_subnet_tags
  outpost_dedicated_network_acl = var.outpost_dedicated_network_acl
  outpost_inbound_acl_rules = var.outpost_inbound_acl_rules
  outpost_outbound_acl_rules = var.outpost_outbound_acl_rules
  outpost_acl_tags = var.outpost_acl_tags
  create_igw = var.create_igw
  create_egress_only_igw = var.create_egress_only_igw
  igw_tags = var.igw_tags
  enable_nat_gateway = var.enable_nat_gateway
  nat_gateway_destination_cidr_block = var.nat_gateway_destination_cidr_block
  reuse_nat_ips = var.reuse_nat_ips
  external_nat_ip_ids = var.external_nat_ip_ids
  external_nat_ips = var.external_nat_ips
  nat_gateway_tags = var.nat_gateway_tags
  nat_eip_tags = var.nat_eip_tags
  customer_gateways = var.customer_gateways
  customer_gateway_tags = var.customer_gateway_tags
  enable_vpn_gateway = var.enable_vpn_gateway
  vpn_gateway_id = var.vpn_gateway_id
  amazon_side_asn = var.amazon_side_asn
  vpn_gateway_az = var.vpn_gateway_az
  propagate_intra_route_tables_vgw = var.propagate_intra_route_tables_vgw
  propagate_private_route_tables_vgw = var.propagate_private_route_tables_vgw
  propagate_public_route_tables_vgw = var.propagate_public_route_tables_vgw
  vpn_gateway_tags = var.vpn_gateway_tags
  manage_default_vpc = var.manage_default_vpc
  default_vpc_name = var.default_vpc_name
  default_vpc_enable_dns_support = var.default_vpc_enable_dns_support
  default_vpc_enable_dns_hostnames = var.default_vpc_enable_dns_hostnames
  default_vpc_tags = var.default_vpc_tags
  manage_default_security_group = var.manage_default_security_group
  default_security_group_name = var.default_security_group_name
  default_security_group_ingress = var.default_security_group_ingress
  default_security_group_egress = var.default_security_group_egress
  default_security_group_tags = var.default_security_group_tags
  manage_default_network_acl = var.manage_default_network_acl
  default_network_acl_name = var.default_network_acl_name
  default_network_acl_ingress = var.default_network_acl_ingress
  default_network_acl_egress = var.default_network_acl_egress
  default_network_acl_tags = var.default_network_acl_tags
  manage_default_route_table = var.manage_default_route_table
  default_route_table_name = var.default_route_table_name
  default_route_table_propagating_vgws = var.default_route_table_propagating_vgws
  default_route_table_routes = var.default_route_table_routes
  default_route_table_tags = var.default_route_table_tags
  enable_flow_log = var.enable_flow_log
  vpc_flow_log_permissions_boundary = var.vpc_flow_log_permissions_boundary
  flow_log_max_aggregation_interval = var.flow_log_max_aggregation_interval
  flow_log_traffic_type = var.flow_log_traffic_type
  flow_log_destination_type = var.flow_log_destination_type
  flow_log_log_format = var.flow_log_log_format
  flow_log_destination_arn = var.flow_log_destination_arn
  flow_log_file_format = var.flow_log_file_format
  flow_log_hive_compatible_partitions = var.flow_log_hive_compatible_partitions
  flow_log_per_hour_partition = var.flow_log_per_hour_partition
  vpc_flow_log_tags = var.vpc_flow_log_tags
  create_flow_log_cloudwatch_log_group = var.create_flow_log_cloudwatch_log_group
  create_flow_log_cloudwatch_iam_role = var.create_flow_log_cloudwatch_iam_role
  flow_log_cloudwatch_iam_role_arn = var.flow_log_cloudwatch_iam_role_arn
  flow_log_cloudwatch_log_group_name_prefix = var.flow_log_cloudwatch_log_group_name_prefix
  flow_log_cloudwatch_log_group_name_suffix = var.flow_log_cloudwatch_log_group_name_suffix
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_cloudwatch_log_group_kms_key_id = var.flow_log_cloudwatch_log_group_kms_key_id
}
