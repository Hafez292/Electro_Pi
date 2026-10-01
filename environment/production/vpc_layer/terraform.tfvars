cidr_vpc = "10.0.0.0/16"
tag  = "Electro_Pi"
azs = ["us-east-1a", "us-east-1d", "us-east-1c"]
cidr_Public_Subnets = {
    Electro_Public_Subnet_1 = "10.0.1.0/24"
    Electro_Public_Subnet_2 = "10.0.2.0/24"
}
cidr_Private_Subnets = {
    Electro_Private_Subnet_1 = "10.0.3.0/24"
    Electro_Private_Subnet_2 = "10.0.4.0/24"
}
enable_dns_hostnames = true