variable "cidr_vpc" {
    type = string
}

variable "tag_vpc" {
    type = string
}

variable "cidr_Pub_Subnets" {
    type = map(string) 
}

variable "cidr_Pri_Subnets" {
    type = map(string)
  
}

variable "azs" {
  description = "List of AZs for subnets"
  type        = list(string)
}


variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = null
  
}
