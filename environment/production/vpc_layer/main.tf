module "vpc" {
    source = "../../../modules/vpc"
    cidr_vpc = var.cidr_vpc
    tag_vpc = var.tag
    cidr_Pub_Subnets = var.cidr_Public_Subnets
    cidr_Pri_Subnets = var.cidr_Private_Subnets
    azs = var.azs
    enable_dns_hostnames = var.enable_dns_hostnames
}